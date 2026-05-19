#!/bin/bash

WALLPAPER_DIR="/home/hamo/Pictures/Live wall"
STATIC_DIR="/home/hamo/Pictures/Wallpapers"
IPC_SOCKET="/tmp/mpv-wallpaper.sock"
MONITOR="eDP-1"
INDEX_FILE="/tmp/wallpaper-index"

get_files() {
    local dir="$1" ext="$2"
    local files=()
    for f in "$dir"/*."$ext"; do [ -f "$f" ] && files+=("$f"); done
    echo "${files[@]}"
}

next_file() {
    local dir="$1" mode="$2"
    local files=()
    case "$mode" in
        video) mapfile -t files < <(ls "$dir"/*.{mp4,webm,MP4,WEBM} 2>/dev/null) ;;
        image) mapfile -t files < <(ls "$dir"/*.{png,jpg,jpeg,PNG,JPG,JPEG} 2>/dev/null) ;;
    esac
    local count=${#files[@]}
    [ "$count" -eq 0 ] && return 1

    local idx=0
    if [ -f "$INDEX_FILE-$mode" ]; then
        idx=$(<"$INDEX_FILE-$mode")
    fi
    idx=$(( (idx + 1) % count ))
    echo "$idx" > "$INDEX_FILE-$mode"
    echo "${files[$idx]}"
}

live() {
    pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
    awww kill 2>/dev/null
    sleep 0.3
    local video
    video=$(next_file "$WALLPAPER_DIR" video)
    [ -z "$video" ] && notify-send "Wallpaper" "No videos found" && exit 1
    mpvpaper -f -l bottom -o "--input-ipc-server=$IPC_SOCKET no-audio loop" "$MONITOR" "$video"
    notify-send "Wallpaper" "Live: $(basename "$video")"
}

stop() {
    pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
    rm -f "$IPC_SOCKET"
    rm -f /tmp/current-static-wallpaper
}

static() {
    pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
    if ! pgrep -x "awww-daemon" >/dev/null 2>&1; then
        nohup awww-daemon >/dev/null 2>&1 &
        sleep 1
    fi
    local image
    if [ -n "$1" ] && [ -f "$1" ]; then
        image="$1"
    else
        image=$(next_file "$STATIC_DIR" image)
    fi
    [ -z "$image" ] && notify-send "Wallpaper" "No images found" && exit 1
    echo "$(basename "$image")" > /tmp/current-static-wallpaper
    awww img "$image" 2>/dev/null
    notify-send "Wallpaper" "Static: $(basename "$image")"
}

toggle() {
    if [ -S "$IPC_SOCKET" ]; then
        echo 'cycle pause' | socat - "$IPC_SOCKET" 2>/dev/null
    fi
}

case "${1:-}" in
    live)    live ;;
    stop)    stop ;;
    static)  static "$2" ;;
    toggle)  toggle ;;
    *)
        echo "Usage: $0 {live|stop|static|toggle}"
        exit 1
        ;;
esac
