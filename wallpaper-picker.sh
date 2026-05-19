#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

IPC_SOCKET="/tmp/mpv-wallpaper.sock"
TRACKING_FILE="/tmp/current-static-wallpaper"

ICON_VIDEO="󰎁"
ICON_IMAGE="󰋩"
ICON_CURRENT="●"
ICON_INACTIVE="○"

current_live=""
current_static=""

get_current_live() {
    [ -S "$IPC_SOCKET" ] || return
    local pid
    pid=$(pgrep -f "mpvpaper.*$MONITOR" 2>/dev/null | head -1)
    [ -n "$pid" ] && ps -p "$pid" -o args= 2>/dev/null | grep -oP "\Q$LIVE_DIR\E/[^ ]+(?=\s|$)"
}

get_current_static() {
    [ -f "$TRACKING_FILE" ] && cat "$TRACKING_FILE"
}

for_each_video() {
    local dir="$1" cmd="$2"; shift 2
    local f
    for f in "$dir"/*.mp4 "$dir"/*.webm "$dir"/*.MP4 "$dir"/*.WEBM; do
        [ -f "$f" ] || continue
        "$cmd" "$f" "$@"
    done
}

for_each_image() {
    local dir="$1" cmd="$2"; shift 2
    local f
    for f in "$dir"/*.png "$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.PNG "$dir"/*.JPG "$dir"/*.JPEG; do
        [ -f "$f" ] || continue
        "$cmd" "$f" "$@"
    done
}

build_menu() {
    local mode="$1"
    current_live=$(get_current_live)
    current_static=$(get_current_static)
    local has_live=false

    if [ "$mode" = "all" ] || [ "$mode" = "live" ]; then
        for f in "$LIVE_DIR"/*.mp4 "$LIVE_DIR"/*.webm "$LIVE_DIR"/*.MP4 "$LIVE_DIR"/*.WEBM; do
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
        for f in "$STATIC_DIR"/*.png "$STATIC_DIR"/*.jpg "$STATIC_DIR"/*.jpeg "$STATIC_DIR"/*.PNG "$STATIC_DIR"/*.JPG "$STATIC_DIR"/*.JPEG; do
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
    printf "  Open Wallpaper Folder\n"
    printf "󰋼  Change Folders\n"
    printf "󰃣  Set as Default\n"
    printf "󰑓  Refresh\n"
}

resolve_file() {
    local name="$1"
    for f in "$LIVE_DIR"/*.mp4 "$LIVE_DIR"/*.webm "$LIVE_DIR"/*.MP4 "$LIVE_DIR"/*.WEBM; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "$b" = "$name" ] && echo "$f" && return
        [ "${b%.*}" = "$name" ] && echo "$f" && return
    done
    for f in "$STATIC_DIR"/*.png "$STATIC_DIR"/*.jpg "$STATIC_DIR"/*.jpeg "$STATIC_DIR"/*.PNG "$STATIC_DIR"/*.JPG "$STATIC_DIR"/*.JPEG; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "$b" = "$name" ] && echo "$f" && return
        [ "${b%.*}" = "$name" ] && echo "$f" && return
    done
}

choose_folder() {
    local prompt="$1"
    local choice
    choice=$(zenity --file-selection --directory --title="$prompt" 2>/dev/null)
    echo "$choice"
}

change_folders() {
    local new_live new_static new_mon

    new_live=$(choose_folder "Select Live Wallpaper Folder")
    [ -z "$new_live" ] && return 1

    new_static=$(choose_folder "Select Static Wallpaper Folder")
    [ -z "$new_static" ] && return 1

    new_mon=$(zenity --entry --title="Monitor" --text="Enter monitor name:" --entry-text="$MONITOR" 2>/dev/null)
    [ -z "$new_mon" ] && new_mon="$MONITOR"

    cat > "$SCRIPT_DIR/wallpaper-config.sh" << EOF
LIVE_DIR="$new_live"
STATIC_DIR="$new_static"
MONITOR="$new_mon"
EOF

    LIVE_DIR="$new_live"
    STATIC_DIR="$new_static"
    MONITOR="$new_mon"

    systemctl --user restart wallpaper-watcher.service 2>/dev/null

    notify-send "Wallpaper" "Folders updated to:\nLive: $new_live\nStatic: $new_static"
}

set_default() {
    local active=""

    if [ -S "$IPC_SOCKET" ]; then
        local pid
        pid=$(pgrep -f "mpvpaper.*$MONITOR" 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            active=$(ps -p "$pid" -o args= 2>/dev/null | grep -oP "\Q$LIVE_DIR\E/[^ ]+" | head -1)
        fi
    fi

    if [ -z "$active" ] && [ -f "$TRACKING_FILE" ]; then
        local name
        name=$(cat "$TRACKING_FILE")
        [ -f "$STATIC_DIR/$name" ] && active="$STATIC_DIR/$name"
    fi

    if [ -z "$active" ]; then
        notify-send "Wallpaper" "No active wallpaper to set as default"
        return 1
    fi

    local escaped
    escaped=$(printf '%s\n' "$active" | sed 's/[\/&]/\\&/g')
    sed -i "s|^DEFAULT_WALLPAPER=.*|DEFAULT_WALLPAPER=\"$escaped\"|" "$SCRIPT_DIR/wallpaper-config.sh"

    source "$SCRIPT_DIR/wallpaper-config.sh"
    notify-send "Wallpaper" "Default set: $(basename "$active")"
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
        *"Open Wallpaper Folder"*)
            thunar "$LIVE_DIR" &
            exit 0
            ;;
        *"Change Folders"*)
            change_folders
            show_picker "$mode"
            return
            ;;
        *"Set as Default"*)
            set_default
            show_picker "$mode"
            return
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
    [ -n "$filepath" ] && apply_wallpaper "$filepath"
}

random_wallpaper() {
    local files=()
    for f in "$LIVE_DIR"/*.mp4 "$LIVE_DIR"/*.webm "$LIVE_DIR"/*.MP4 "$LIVE_DIR"/*.WEBM; do [ -f "$f" ] && files+=("$f"); done
    for f in "$STATIC_DIR"/*.png "$STATIC_DIR"/*.jpg "$STATIC_DIR"/*.jpeg "$STATIC_DIR"/*.PNG "$STATIC_DIR"/*.JPG "$STATIC_DIR"/*.JPEG; do [ -f "$f" ] && files+=("$f"); done
    [ ${#files[@]} -eq 0 ] && notify-send "Wallpaper" "No wallpapers found" && exit 1
    local pick
    pick=${files[$RANDOM % ${#files[@]}]}
    apply_wallpaper "$pick"
}

apply_wallpaper() {
    local file="$1"
    case "$file" in
        *.mp4|*.webm|*.MP4|*.WEBM)
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
