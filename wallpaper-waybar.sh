#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

IPC_SOCKET="/tmp/mpv-wallpaper.sock"
TRACKING_FILE="/tmp/current-static-wallpaper"

get_current_live() {
    if [ -S "$IPC_SOCKET" ]; then
        local pid
        pid=$(pgrep -f "mpvpaper.*$MONITOR" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            ps -p "$pid" -o args= 2>/dev/null | grep -oP "\Q$LIVE_DIR\E/[^ ]+(?=\s|$)"
        fi
    fi
}

get_current_static() {
    if [ -f "$TRACKING_FILE" ]; then
        cat "$TRACKING_FILE"
    fi
}

if [ -S "$IPC_SOCKET" ]; then
    name=$(get_current_live)
    if [ -n "$name" ]; then
        printf '{"text":"󰎁 %s","tooltip":"Live: %s\\nClick: Picker | Scroll: Cycle | Middle: Pause","class":"live"}\n' "$name" "$name"
        exit 0
    fi
fi

name=$(get_current_static)
if [ -n "$name" ]; then
    printf '{"text":"󰋩 %s","tooltip":"Static: %s\\nClick: Picker | Scroll: Cycle","class":"static"}\n' "$name" "$name"
    exit 0
fi

printf '{"text":"󰱟 none","tooltip":"No wallpaper active\\nClick: Open Picker","class":"none"}\n'
