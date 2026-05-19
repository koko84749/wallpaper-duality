#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

IPC_SOCKET="/tmp/mpv-wallpaper.sock"
INDEX_FILE="/tmp/wallpaper-index"

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
    [ -f "$INDEX_FILE-$mode" ] && idx=$(<"$INDEX_FILE-$mode")
    idx=$(( (idx + 1) % count ))
    echo "$idx" > "$INDEX_FILE-$mode"
    echo "${files[$idx]}"
}

live() {
    pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
    awww kill 2>/dev/null
    sleep 0.3
    local video
    video=$(next_file "$LIVE_DIR" video)
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
    [ -S "$IPC_SOCKET" ] && echo 'cycle pause' | socat - "$IPC_SOCKET" 2>/dev/null
}

default() {
    if [ -n "$DEFAULT_WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
        case "$DEFAULT_WALLPAPER" in
            *.mp4|*.webm|*.MP4|*.WEBM)
                pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
                awww kill 2>/dev/null
                sleep 0.3
                mpvpaper -f -l bottom -o "--input-ipc-server=$IPC_SOCKET no-audio loop" "$MONITOR" "$DEFAULT_WALLPAPER"
                notify-send "Wallpaper" "Default: $(basename "$DEFAULT_WALLPAPER")"
                ;;
            *.png|*.jpg|*.jpeg|*.PNG|*.JPG|*.JPEG)
                pkill -f "mpvpaper.*$MONITOR" 2>/dev/null
                if ! pgrep -x "awww-daemon" >/dev/null 2>&1; then
                    nohup awww-daemon >/dev/null 2>&1 &
                    sleep 1
                fi
                echo "$(basename "$DEFAULT_WALLPAPER")" > /tmp/current-static-wallpaper
                awww img "$DEFAULT_WALLPAPER" 2>/dev/null
                notify-send "Wallpaper" "Default: $(basename "$DEFAULT_WALLPAPER")"
                ;;
        esac
    else
        notify-send "Wallpaper" "No default wallpaper set"
        exit 1
    fi
}

case "${1:-}" in
    live)    live ;;
    stop)    stop ;;
    static)  static "$2" ;;
    default) default ;;
    toggle)  toggle ;;
    *)
        echo "Usage: $0 {live|stop|static|toggle|default}"
        exit 1
        ;;
esac
