#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

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
        *.mp4|*.webm|*.png|*.jpg|*.jpeg|*.MP4|*.WEBM|*.PNG|*.JPG|*.JPEG)
            notify-send -t 8000 \
                "Wallpaper Watcher" \
                "New: $(basename "$fullpath")"
            ;;
    esac
done
