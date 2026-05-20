#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

VIDEO_EXTS=("mp4" "webm" "avi" "mkv" "mov" "gif")
IMAGE_EXTS=("png" "jpg" "jpeg" "bmp" "webp")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
info() { echo -e "${CYAN}[*]${NC} $1"; }

detect_type_by_ext() {
    local file="$1" name ext
    name=$(basename "$file")
    ext="${name##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    for v in "${VIDEO_EXTS[@]}"; do
        [ "$ext" = "$v" ] && echo "video" && return
    done
    for i in "${IMAGE_EXTS[@]}"; do
        [ "$ext" = "$i" ] && echo "image" && return
    done
    echo "unknown"
}

detect_type_by_mime() {
    local file="$1" mime
    mime=$(file --mime-type -b "$file" 2>/dev/null)
    case "$mime" in
        video/*|image/gif) echo "video" ;;
        image/*) echo "image" ;;
        *) echo "unknown" ;;
    esac
}

detect_type() {
    local file="$1"
    local by_ext
    by_ext=$(detect_type_by_ext "$file")
    [ "$by_ext" != "unknown" ] && echo "$by_ext" && return
    detect_type_by_mime "$file"
}

sort_file() {
    local file="$1" type="$2"
    local dest_dir=""
    [ "$type" = "video" ] && dest_dir="$LIVE_DIR"
    [ "$type" = "image" ] && dest_dir="$STATIC_DIR"

    local name
    name=$(basename "$file")

    if [ "$(dirname "$file")" = "$dest_dir" ]; then
        return
    fi

    if [ -f "$dest_dir/$name" ]; then
        name="${name%.*}_$(date +%s).${name##*.}"
    fi

    mv "$file" "$dest_dir/$name" 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Moved: $(basename "$file") → $dest_dir/ ($type)"
        return 0
    else
        err "Failed to move: $file"
        return 1
    fi
}

scan_and_sort() {
    local moved=0

    info "Scanning $LIVE_DIR for misplaced files..."
    for f in "$LIVE_DIR"/*; do
        [ -f "$f" ] || continue
        local type
        type=$(detect_type "$f")
        if [ "$type" = "image" ]; then
            sort_file "$f" "image"
            moved=$((moved + 1))
        fi
    done

    info "Scanning $STATIC_DIR for misplaced files..."
    for f in "$STATIC_DIR"/*; do
        [ -f "$f" ] || continue
        local type
        type=$(detect_type "$f")
        if [ "$type" = "video" ]; then
            sort_file "$f" "video"
            moved=$((moved + 1))
        fi
    done

    [ "$moved" -eq 0 ] && info "All files are correctly sorted"
}

fix_sort() {
    info "Running --fix mode (deep scan with MIME type verification)..."
    scan_and_sort
}

watch_sort() {
    info "Starting watch mode on $LIVE_DIR and $STATIC_DIR..."
    info "Press Ctrl+C to stop"

    if ! command -v inotifywait &>/dev/null; then
        err "inotifywait not found. Install inotify-tools"
        exit 1
    fi

    inotifywait -q -m -e close_write -e moved_to \
        "$LIVE_DIR" "$STATIC_DIR" --format "%w%f" 2>/dev/null | while read -r fullpath; do

        [ ! -f "$fullpath" ] && continue

        local type
        type=$(detect_type "$fullpath")
        local dest_dir=""
        [ "$type" = "video" ] && dest_dir="$LIVE_DIR"
        [ "$type" = "image" ] && dest_dir="$STATIC_DIR"

        if [ "$dest_dir" != "$(dirname "$fullpath")" ] && [ -n "$dest_dir" ]; then
            sort_file "$fullpath" "$type"
        fi
    done
}

usage() {
    echo "Usage: $0 [OPTION]"
    echo "Sort wallpaper files into correct directories by type"
    echo ""
    echo "Options:"
    echo "  (no args)  Scan and sort misplaced files"
    echo "  --fix      Deep scan with MIME verification"
    echo "  -w, --watch  Watch directories and auto-sort new files"
    echo "  -h, --help   Show this help"
}

case "${1:-}" in
    --fix)    fix_sort ;;
    -w|--watch) watch_sort ;;
    -h|--help) usage ;;
    "")       scan_and_sort ;;
    *)
        if [ -f "$1" ]; then
            t=$(detect_type "$1")
            echo "$t"
        else
            usage
        fi
        ;;
esac
