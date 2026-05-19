#!/bin/bash

LIVE_DIR="/home/hamo/Pictures/Live wall"
STATIC_DIR="/home/hamo/Pictures/Wallpapers"
SCRIPT_DIR="/home/hamo/.config/hypr/Scripts"
IPC_SOCKET="/tmp/mpv-wallpaper.sock"
MONITOR="eDP-1"

ICON_VIDEO="󰎁"
ICON_IMAGE="󰋩"
ICON_CURRENT="●"
ICON_INACTIVE="○"

get_current_live() {
    if [ -S "$IPC_SOCKET" ]; then
        local pid
        pid=$(pgrep -f "mpvpaper.*$MONITOR" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            ps -p "$pid" -o args= 2>/dev/null | grep -oP "/home/hamo/Pictures/Live wall/\K[^.]+"
        fi
    fi
}

TRACKING_FILE="/tmp/current-static-wallpaper"

get_current_static() {
    if [ -f "$TRACKING_FILE" ]; then
        cat "$TRACKING_FILE"
    fi
}

build_menu() {
    local mode="$1"
    local current_live current_static
    current_live=$(get_current_live)
    current_static=$(get_current_static)
    local has_live=false

    if [ "$mode" = "all" ] || [ "$mode" = "live" ]; then
        for f in "$LIVE_DIR"/*.{mp4,webm,MP4,WEBM}; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            if [ "$name" = "$current_live" ]; then
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_VIDEO" "$name" "$f"
            else
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_VIDEO" "$name" "$f"
            fi
            has_live=true
        done
    fi

    if [ "$mode" = "all" ] && [ "$has_live" = true ]; then
        printf "───  ───\n"
    fi

    if [ "$mode" = "all" ] || [ "$mode" = "static" ]; then
        for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            if [ "$name" = "$current_static" ]; then
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_IMAGE" "$name" "$f"
            else
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_IMAGE" "$name" "$f"
            fi
        done
    fi

    printf "───  ───\n"
    printf "󰅖  Clear Wallpaper\n"
    printf "󰑐  Random Wallpaper\n"
    printf "  Open Wallpapers Folder\n"
    printf "󰑓  Refresh\n"
}

resolve_file() {
    local name="$1"
    for f in "$LIVE_DIR"/*.{mp4,webm,MP4,WEBM}; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "$b" = "$name" ] && echo "$f" && return
        [ "${b%.*}" = "$name" ] && echo "$f" && return
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG}; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "$b" = "$name" ] && echo "$f" && return
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG}; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "${b%.*}" = "$name" ] && echo "$f" && return
    done
}

show_picker() {
    local mode="${1:-all}"
    local mode_label="All"
    [ "$mode" = "live" ] && mode_label="Live"
    [ "$mode" = "static" ] && mode_label="Static"

    local chosen
    chosen=$(build_menu "$mode" | rofi -dmenu -p "Wallpaper" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" \
        -show-icons -icon-theme Papirus \
        -mesg "Mode: $mode_label | Alt+1: All · Alt+2: Live · Alt+3: Static · Alt+4: Random · Alt+5: Refresh" \
        -kb-custom-1 "Alt+1" \
        -kb-custom-2 "Alt+2" \
        -kb-custom-3 "Alt+3" \
        -kb-custom-4 "Alt+4" \
        -kb-custom-5 "Alt+5" \
        -i 2>/dev/null)
    local exit_code=$?

    [ $exit_code -ge 10 ] && [ $exit_code -le 14 ] && {
        local new_mode
        case $exit_code in
            10) new_mode="all" ;;
            11) new_mode="live" ;;
            12) new_mode="static" ;;
            13) random_wallpaper ; return ;;
            14) show_picker "$mode" ; return ;;
        esac
        show_picker "$new_mode"
        return
    }

    [ -z "$chosen" ] && exit 0

    case "$chosen" in
        *"Clear Wallpaper"*)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            rm -f "$TRACKING_FILE"
            notify-send "Wallpaper" "Cleared"
            exit 0
            ;;
        *"Random Wallpaper"*)
            random_wallpaper
            return
            ;;
        *"Open Wallpapers Folder"*)
            thunar "$LIVE_DIR" &
            exit 0
            ;;
        *"Refresh"*)
            show_picker "$mode"
            return
            ;;
        *"───"*)
            show_picker "$mode"
            return
            ;;
    esac

    local name
    name=$(echo "$chosen" | awk '{$1=$2=""; print $0}' | xargs)

    local filepath
    filepath=$(resolve_file "$name")

    [ -z "$filepath" ] && exit 0

    apply_wallpaper "$filepath"
}

random_wallpaper() {
    local files=()
    for f in "$LIVE_DIR"/*.{mp4,webm,MP4,WEBM}; do
        [ -f "$f" ] && files+=("$f")
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG}; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -eq 0 ] && notify-send "Wallpaper" "No wallpapers found" && exit 1

    local pick
    pick=${files[$RANDOM % ${#files[@]}]}
    apply_wallpaper "$pick"
}

apply_wallpaper() {
    local file="$1"
    case "$file" in
        *.mp4|*.webm)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            name=$(basename "$file")
            mpvpaper -f -l bottom -o "--input-ipc-server=$IPC_SOCKET no-audio loop" "$MONITOR" "$file"
            notify-send "Wallpaper" "Live: $name"
            ;;
        *.png|*.jpg|*.jpeg|*.PNG|*.JPG|*.JPEG)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            if ! pgrep -x "awww-daemon" >/dev/null 2>&1; then
                nohup awww-daemon >/dev/null 2>&1 &
                sleep 1
            fi
            name=$(basename "$file")
            echo "$name" > "$TRACKING_FILE"
            awww img "$file" 2>/dev/null
            notify-send "Wallpaper" "Static: $name"
            ;;
    esac
}

case "${1:-}" in
    live)    show_picker "live" ;;
    static)  show_picker "static" ;;
    random)  random_wallpaper ;;
    *)       show_picker "all" ;;
esac
