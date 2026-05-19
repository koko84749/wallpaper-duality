#!/bin/bash

set -e

SCRIPT_DIR="$HOME/.config/hypr/Scripts"
LIVE_DIR="$HOME/Pictures/Live wall"
STATIC_DIR="$HOME/Pictures/Wallpapers"
CONFIG_DIR="$HOME/.config/hypr"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
info() { echo -e "${CYAN}[*]${NC} $1"; }

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   Hyprland Wallpaper System Installer ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

detect_monitor() {
    if command -v hyprctl &>/dev/null; then
        local mon
        mon=$(hyprctl monitors -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['name'])" 2>/dev/null)
        [ -n "$mon" ] && echo "$mon" && return
    fi
    echo "eDP-1"
}

install_packages() {
    echo ""
    info "Detecting package manager..."

    local pkgs=()
    if command -v pacman &>/dev/null; then
        log "Arch Linux detected (pacman)"
        pkgs=(mpv mpvpaper awww rogi ffmpegthumbnailer libnotify thunar ttf-jetbrains-mono-nerd)
        local missing=()
        for p in "${pkgs[@]}"; do
            pacman -Qi "$p" &>/dev/null || missing+=("$p")
        done
        if [ ${#missing[@]} -gt 0 ]; then
            log "Installing: ${missing[*]}"
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        else
            log "All packages already installed"
        fi
    elif command -v apt &>/dev/null; then
        log "Debian/Ubuntu detected (apt)"
        pkgs=(mpv mpvpaper ffmpegthumbnailer libnotify-bin thunar fonts-jetbrains-mono)
        warn "awww and rofi may not be in official repos — install from source or use a PPA"
        warn "Rofi 2.0+ with thumbnail support is required"
        local missing=()
        for p in "${pkgs[@]}"; do
            dpkg -s "$p" &>/dev/null 2>&1 || missing+=("$p")
        done
        if [ ${#missing[@]} -gt 0 ]; then
            log "Installing: ${missing[*]}"
            sudo apt install -y "${missing[@]}"
        fi
    elif command -v dnf &>/dev/null; then
        log "Fedora detected (dnf)"
        pkgs=(mpv mpvpaper ffmpegthumbnailer libnotify thunar jetbrains-mono-fonts)
        local missing=()
        for p in "${pkgs[@]}"; do
            rpm -q "$p" &>/dev/null || missing+=("$p")
        done
        if [ ${#missing[@]} -gt 0 ]; then
            log "Installing: ${missing[*]}"
            sudo dnf install -y "${missing[@]}"
        fi
    else
        warn "Unknown distro. Please install manually:"
        warn "  mpv mpvpaper awww rogi ffmpegthumbnailer libnotify thunar"
    fi

    if ! command -v rogi &>/dev/null; then
        warn "rogi (Rofi 2.0+) not found — needed for the thumbnail wallpaper picker"
        warn "Install it from https://github.com/davatorium/rofi"
    fi
    if ! command -v awww &>/dev/null; then
        warn "awww not found — needed for static wallpaper support"
        warn "Install it from https://github.com/find-drama/awww"
    fi
}

setup_dirs() {
    echo ""
    info "Setting up directories..."

    mkdir -p "$SCRIPT_DIR"
    mkdir -p "$LIVE_DIR"
    mkdir -p "$STATIC_DIR"
    mkdir -p "$CONFIG_DIR"

    log "Created: $SCRIPT_DIR"
    log "Created: $LIVE_DIR (put .mp4 files here)"
    log "Created: $STATIC_DIR (put .png/.jpg files here)"
}

detect_user_paths() {
    echo ""
    info "Detecting paths..."

    local mon
    mon=$(detect_monitor)
    log "Detected monitor: $mon"

    echo ""
    echo -e "  Live wallpaper directory: ${CYAN}$LIVE_DIR${NC}"
    echo -e "  Static wallpaper directory: ${CYAN}$STATIC_DIR${NC}"
    echo -e "  Monitor: ${CYAN}$mon${NC}"
    echo ""

    read -r -p "  Change live dir? (leave blank for default): " user_live
    LIVE_DIR="${user_live:-$LIVE_DIR}"

    read -r -p "  Change static dir? (leave blank for default): " user_static
    STATIC_DIR="${user_static:-$STATIC_DIR}"

    read -r -p "  Change monitor? (leave blank for $mon): " user_mon
    MONITOR="${user_mon:-$mon}"
}

create_scripts() {
    echo ""
    info "Creating script files..."

    # Escape paths for sed replacement
    local live_esc
    live_esc=$(printf '%s\n' "$LIVE_DIR" | sed 's/[\/&]/\\&/g')
    local static_esc
    static_esc=$(printf '%s\n' "$STATIC_DIR" | sed 's/[\/&]/\\&/g')
    local script_esc
    script_esc=$(printf '%s\n' "$SCRIPT_DIR" | sed 's/[\/&]/\\&/g')

    # ─── wallpaperctl.sh ───
    cat > "$SCRIPT_DIR/wallpaperctl.sh" << 'WCTLEOF'
#!/bin/bash

WALLPAPER_DIR="__LIVE_DIR__"
STATIC_DIR="__STATIC_DIR__"
IPC_SOCKET="/tmp/mpv-wallpaper.sock"
MONITOR="__MONITOR__"
INDEX_FILE="/tmp/wallpaper-index"

next_file() {
    local dir="$1" mode="$2"
    local files=()
    case "$mode" in
        video) mapfile -t files < <(ls "$dir"/*.mp4 2>/dev/null) ;;
        image) mapfile -t files < <(ls "$dir"/*.{png,jpg,jpeg} 2>/dev/null) ;;
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
    image=$(next_file "$STATIC_DIR" image)
    [ -z "$image" ] && notify-send "Wallpaper" "No images found" && exit 1
    echo "$(basename "$image")" > /tmp/current-static-wallpaper
    awww img "$image" 2>/dev/null
    notify-send "Wallpaper" "Static: $(basename "$image")"
}

toggle() {
    [ -S "$IPC_SOCKET" ] && echo 'cycle pause' | socat - "$IPC_SOCKET" 2>/dev/null
}

case "${1:-}" in
    live)   live ;;
    stop)   stop ;;
    static) static ;;
    toggle) toggle ;;
    *)
        echo "Usage: $0 {live|stop|static|toggle}"
        exit 1
        ;;
esac
WCTLEOF

    # ─── wallpaper-picker.sh ───
    cat > "$SCRIPT_DIR/wallpaper-picker.sh" << 'WPEOF'
#!/bin/bash

LIVE_DIR="__LIVE_DIR__"
STATIC_DIR="__STATIC_DIR__"
SCRIPT_DIR="__SCRIPT_DIR__"
IPC_SOCKET="/tmp/mpv-wallpaper.sock"
MONITOR="__MONITOR__"

ICON_VIDEO="\xf0\x9f\x8e\xac"
ICON_IMAGE="\xf0\x9f\x96\xbc"
ICON_CURRENT="\xe2\x97\x89"
ICON_INACTIVE="\xe2\x97\x8b"

get_current_live() {
    [ -S "$IPC_SOCKET" ] || return
    local pid
    pid=$(pgrep -f "mpvpaper.*$MONITOR" 2>/dev/null | head -1)
    [ -n "$pid" ] && ps -p "$pid" -o args= 2>/dev/null | grep -oP "__LIVE_DIR__/\K[^.]+"
}

TRACKING_FILE="/tmp/current-static-wallpaper"

get_current_static() {
    [ -f "$TRACKING_FILE" ] && cat "$TRACKING_FILE"
}

build_menu() {
    local mode="$1"
    local current_live current_static
    current_live=$(get_current_live)
    current_static=$(get_current_static)
    local has_live=false

    if [ "$mode" = "all" ] || [ "$mode" = "live" ]; then
        for f in "$LIVE_DIR"/*.mp4; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .mp4)
            if [ "$name" = "$current_live" ]; then
                printf "%b %b %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_VIDEO" "$name" "$f"
            else
                printf "%b %b %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_VIDEO" "$name" "$f"
            fi
            has_live=true
        done
    fi

    if [ "$mode" = "all" ] && [ "$has_live" = true ]; then
        printf "\342\200\224\342\200\224\342\200\224  \357\232\227 \342\200\224\342\200\224\342\200\224\n"
    fi

    if [ "$mode" = "all" ] || [ "$mode" = "static" ]; then
        for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            if [ "$name" = "$current_static" ]; then
                printf "%b %b %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_IMAGE" "$name" "$f"
            else
                printf "%b %b %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_IMAGE" "$name" "$f"
            fi
        done
    fi

    printf "\342\200\224\342\200\224\342\200\224  \357\233\234 \342\200\224\342\200\224\342\200\224\n"
    printf "\360\237\227\221  Clear Wallpaper\n"
    printf "\360\237\224\200  Random Wallpaper\n"
    printf "\360\237\223\202  Open Wallpapers Folder\n"
}

resolve_file() {
    local name="$1"
    for f in "$LIVE_DIR"/*.mp4; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .mp4)
        [ "$b" = "$name" ] && echo "$f" && return
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do
        [ -f "$f" ] || continue
        b=$(basename "$f")
        [ "$b" = "$name" ] && echo "$f" && return
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do
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
        -show-icons \
        -mesg "Mode: $mode_label | Alt+1: All \302\267 Alt+2: Live \302\267 Alt+3: Static \302\267 Alt+4: Random" \
        -kb-custom-1 "Alt+1" \
        -kb-custom-2 "Alt+2" \
        -kb-custom-3 "Alt+3" \
        -kb-custom-4 "Alt+4" \
        -i 2>/dev/null)
    local exit_code=$?

    [ $exit_code -ge 10 ] && [ $exit_code -le 13 ] && {
        local new_mode
        case $exit_code in 10) new_mode="all" ;; 11) new_mode="live" ;; 12) new_mode="static" ;; 13) random_wallpaper ; return ;; esac
        show_picker "$new_mode"
        return
    }

    [ -z "$chosen" ] && exit 0

    case "$chosen" in
        *"Clear Wallpaper"*)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            rm -f "$TRACKING_FILE"
            notify-send "Wallpaper" "Cleared"
            exit 0 ;;
        *"Random Wallpaper"*)
            random_wallpaper ; return ;;
        *"Open Wallpapers Folder"*)
            thunar "$LIVE_DIR" & exit 0 ;;
        *"\342\200\224"*)
            show_picker "$mode" ; return ;;
    esac

    local name
    name=$(echo "$chosen" | awk '{$1=$2=""; print $0}' | xargs)
    local filepath
    filepath=$(resolve_file "$name")
    [ -n "$filepath" ] && apply_wallpaper "$filepath"
}

random_wallpaper() {
    local files=()
    for f in "$LIVE_DIR"/*.mp4; do [ -f "$f" ] && files+=("$f"); done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do [ -f "$f" ] && files+=("$f"); done
    [ ${#files[@]} -eq 0 ] && notify-send "Wallpaper" "No wallpapers found" && exit 1
    local pick
    pick=${files[$RANDOM % ${#files[@]}]}
    apply_wallpaper "$pick"
}

apply_wallpaper() {
    local file="$1"
    case "$file" in
        *.mp4)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            name=$(basename "$file" .mp4)
            mpvpaper -f -l bottom -o "--input-ipc-server=$IPC_SOCKET no-audio loop" "$MONITOR" "$file"
            notify-send "Wallpaper" "Live: $name" ;;
        *.png|*.jpg|*.jpeg)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            if ! pgrep -x "awww-daemon" >/dev/null 2>&1; then
                nohup awww-daemon >/dev/null 2>&1 &
                sleep 1
            fi
            name=$(basename "$file")
            echo "$name" > "$TRACKING_FILE"
            awww img "$file" 2>/dev/null
            notify-send "Wallpaper" "Static: $name" ;;
    esac
}

case "${1:-}" in
    live)   show_picker "live" ;;
    static) show_picker "static" ;;
    random) random_wallpaper ;;
    *)      show_picker "all" ;;
esac
WPEOF

    # ─── wallpaper.rasi ───
    cat > "$SCRIPT_DIR/wallpaper.rasi" << 'RASILEOF'
@theme "/usr/share/rofi/themes/android_notification.rasi"

* {
    font: "JetBrainsMonoNL Nerd Font 11";
}

window {
    width: 600px;
}

element {
    padding: 6px 8px;
    orientation: horizontal;
}

element-icon {
    padding: 0 8px 0 0;
    size: 2.4em;
    vertical-align: 0.5;
}

element-text {
    vertical-align: 0.5;
}

element selected {
    background: #89b4fa;
    foreground: #1e1e2e;
    text-color: #1e1e2e;
}

element selected element-icon {
    color: #1e1e2e;
}

listview {
    padding: 4px;
    spacing: 2px;
    dynamic: true;
}

mainbox {
    padding: 8px;
}

message {
    background: transparent;
    font: "JetBrainsMonoNL Nerd Font 9";
    padding: 4px 12px;
    text-color: #a6adc8;
}

inputbar {
    padding: 6px;
}
RASILEOF

    # Substitute placeholders
    sed -i "s|__LIVE_DIR__|$live_esc|g" "$SCRIPT_DIR/wallpaperctl.sh"
    sed -i "s|__STATIC_DIR__|$static_esc|g" "$SCRIPT_DIR/wallpaperctl.sh"
    sed -i "s|__MONITOR__|$MONITOR|g" "$SCRIPT_DIR/wallpaperctl.sh"

    sed -i "s|__LIVE_DIR__|$live_esc|g" "$SCRIPT_DIR/wallpaper-picker.sh"
    sed -i "s|__STATIC_DIR__|$static_esc|g" "$SCRIPT_DIR/wallpaper-picker.sh"
    sed -i "s|__SCRIPT_DIR__|$script_esc|g" "$SCRIPT_DIR/wallpaper-picker.sh"
    sed -i "s|__MONITOR__|$MONITOR|g" "$SCRIPT_DIR/wallpaper-picker.sh"

    chmod +x "$SCRIPT_DIR/wallpaperctl.sh"
    chmod +x "$SCRIPT_DIR/wallpaper-picker.sh"

    log "Created: $SCRIPT_DIR/wallpaperctl.sh"
    log "Created: $SCRIPT_DIR/wallpaper-picker.sh"
    log "Created: $SCRIPT_DIR/wallpaper.rasi"
}

setup_keybinds() {
    echo ""
    info "Setting up Hyprland keybinds..."

    local kb_file="$CONFIG_DIR/keybinds.conf"
    local kb_line_before='# 6. Wallpaper Controls'
    local kb_entry="
# 6. Wallpaper Controls
bind = SUPER, V, exec, \$HOME/.config/hypr/Scripts/wallpaperctl.sh toggle      #\"Wallpaper Toggle\"
bind = SUPER SHIFT, V, exec, \$HOME/.config/hypr/Scripts/wallpaperctl.sh live   #\"Wallpaper Live\"
bind = SUPER, P, exec, \$HOME/.config/hypr/Scripts/wallpaperctl.sh static       #\"Wallpaper Static\"
bind = SUPER SHIFT, P, exec, \$HOME/.config/hypr/Scripts/wallpaper-picker.sh    #\"Wallpaper Picker\"
"

    if grep -q "wallpaper-picker.sh\|wallpaperctl.sh" "$kb_file" 2>/dev/null; then
        warn "Wallpaper keybinds already exist in $kb_file — skipping"
        return
    fi

    if grep -q "Wallpaper Controls" "$kb_file" 2>/dev/null; then
        warn "Found existing wallpaper section in $kb_file, adding after it..."
        sed -i "/Wallpaper Controls/a\\$kb_entry" "$kb_file"
    else
        echo -e "$kb_entry" >> "$kb_file"
        log "Added wallpaper keybinds to $kb_file"
    fi
}

setup_startup() {
    echo ""
    info "Configuring auto-start..."

    local startup_file="$CONFIG_DIR/startup.conf"

    if grep -q "wallpaperctl.sh live" "$startup_file" 2>/dev/null; then
        warn "Auto-start already configured in $startup_file — skipping"
        return
    fi

    echo ""
    read -r -p "  Auto-start live wallpaper on login? (y/N): " auto_start
    if [[ "$auto_start" =~ ^[Yy]$ ]]; then
        echo -e "\n# Live wallpaper (uses mpvpaper)" >> "$startup_file"
        echo "exec-once = \$HOME/.config/hypr/Scripts/wallpaperctl.sh live" >> "$startup_file"
        log "Added auto-start to $startup_file"
    else
        info "Skipping auto-start"
    fi
}

finalize() {
    echo ""
    info "Making scripts executable..."
    chmod +x "$SCRIPT_DIR/wallpaperctl.sh" "$SCRIPT_DIR/wallpaper-picker.sh" 2>/dev/null

    if command -v hyprctl &>/dev/null; then
        log "Reloading Hyprland config..."
        hyprctl reload 2>/dev/null || warn "Could not reload Hyprland — try 'hyprctl reload' manually"
    fi

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║  Installation Complete!              ║${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "  Next steps:"
    echo "  1. Put .mp4 files in:   $LIVE_DIR"
    echo "  2. Put images in:       $STATIC_DIR"
    echo "  3. Use the keybinds:"
    echo "     SUPER + V         → Toggle pause/resume"
    echo "     SUPER + SHIFT + V → Next live wallpaper"
    echo "     SUPER + P         → Next static wallpaper"
    echo "     SUPER + SHIFT + P → Open wallpaper picker"
    echo ""
    echo "  Run this installer again to reconfigure paths."
}

# ─── Main ───
install_packages
setup_dirs
detect_user_paths
create_scripts
setup_keybinds
setup_startup
finalize
