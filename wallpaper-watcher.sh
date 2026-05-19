#!/bin/bash

LIVE_DIR="/home/hamo/Pictures/Live wall"
STATIC_DIR="/home/hamo/Pictures/Wallpapers"
SCRIPT_DIR="/home/hamo/.config/hypr/Scripts"
PID_FILE="/tmp/wallpaper-watcher.pid"

cleanup() {
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup EXIT INT TERM
echo $$ > "$PID_FILE"

inotifywait -q -m -e create -e moved_to \
    "$LIVE_DIR" "$STATIC_DIR" --format "%w%f" 2>/dev/null | while read -r fullpath; do

    case "$fullpath" in
        *.mp4|*.png|*.jpg|*.jpeg)
            notify-send -t 8000 \
                "Wallpaper Watcher" \
                "New: $(basename "$fullpath")"
            ;;
    esac
done
