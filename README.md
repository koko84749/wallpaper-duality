# Live & Static Wallpaper System for Hyprland

A complete wallpaper management system with keybind controls and a Rofi-based visual picker with thumbnails.  

**New in v2.0:** Auto-detect new wallpapers with inotify watcher + Refresh option in the picker.
**New in v2.1:** Optional Waybar module and Noctalia-shell plugin with live wallpaper status indicators and click/scroll controls.

## Requirements

```bash
# Core
sudo pacman -S mpv mpvpaper awww rogi ffmpegthumbnailer

# Notifications
sudo pacman -S libnotify

# Optional (file manager for "Open Folder" action)
sudo pacman -S thunar

# Nerd Font (for icons in the picker)
sudo pacman -S ttf-jetbrains-mono-nerd

# File watcher (auto-detect new wallpapers)
sudo pacman -S inotify-tools

# Waybar module (optional — for bar status indicator)
sudo pacman -S waybar

# Noctalia-shell plugin (optional — for noctalia bar widget)
yay -S noctalia-qs
```

## Directory Structure

```
~/.config/hypr/Scripts/
├── wallpaper-config.sh      # Shared configuration (paths, monitor)
├── wallpaperctl.sh          # Core control script (cycle, toggle, apply)
├── wallpaper-picker.sh      # Rofi visual picker with thumbnails
├── wallpaper-watcher.sh     # Auto-detect new wallpapers (inotify daemon)
├── wallpaper-waybar.sh      # Waybar status module (optional)
└── wallpaper.rasi           # Rofi theme for the picker

~/.config/systemd/user/
└── wallpaper-watcher.service  # systemd user service for the watcher

~/.config/waybar/
├── config.jsonc             # Waybar config (optional, with wallpaper module)
└── style.css                # Waybar style (optional)

~/.config/noctalia/plugins/wallpaper-duality/  # Noctalia-shell plugin (optional)
├── manifest.json
├── Main.qml
├── BarWidget.qml
└── Settings.qml

~/Pictures/Live wall/        # Put .mp4/.webm video files here
~/Pictures/Wallpapers/       # Put .png/.jpg/.jpeg image files here
```

## Auto-Installer (Recommended)

An auto-installer script is included alongside this guide (`install-wallpapers.sh`).  
It handles everything automatically:

- Detects Arch/Debian/Fedora and installs required packages
- Creates all directories and script files with your paths
- Detects your monitor name
- Adds keybinds to your Hyprland config
- Optionally configures auto-start on login
- Reloads Hyprland when done

```bash
chmod +x install-wallpapers.sh
./install-wallpapers.sh
```

If you prefer to set things up manually, follow the steps below.

## Manual Setup

### File Contents

### 1. `~/.config/hypr/Scripts/wallpaperctl.sh`

```bash
#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Live wall"
STATIC_DIR="$HOME/Pictures/Wallpapers"
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
        video) mapfile -t files < <(ls "$dir"/*.mp4 2>/dev/null) ;;
        image) mapfile -t files < <(ls "$dir"/*.{png,jpg,jpeg} 2>/dev/null) ;;
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
    image=$(next_file "$STATIC_DIR" image)
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
    static)  static ;;
    toggle)  toggle ;;
    *)
        echo "Usage: $0 {live|stop|static|toggle}"
        exit 1
        ;;
esac
```

### 2. `~/.config/hypr/Scripts/wallpaper-picker.sh`

```bash
#!/bin/bash

LIVE_DIR="$HOME/Pictures/Live wall"
STATIC_DIR="$HOME/Pictures/Wallpapers"
SCRIPT_DIR="$HOME/.config/hypr/Scripts"
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
            ps -p "$pid" -o args= 2>/dev/null | grep -oP "$HOME/Pictures/Live wall/\K[^.]+"
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
        for f in "$LIVE_DIR"/*.mp4; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .mp4)
            if [ "$name" = "$current_live" ]; then
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_VIDEO" "$name" "$f"
            else
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_VIDEO" "$name" "$f"
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
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_CURRENT" "$ICON_IMAGE" "$name" "$f"
            else
                printf "%s %s %s\\0icon\\x1fthumbnail://%s\n" "$ICON_INACTIVE" "$ICON_IMAGE" "$name" "$f"
            fi
        done
    fi

    printf "\342\200\224\342\200\224\342\200\224  \357\233\234 \342\200\224\342\200\224\342\200\224\n"
    printf "\357\260\205\226  Clear Wallpaper\n"
    printf "\357\260\235\220  Random Wallpaper\n"
    printf "\357\204\225  Open Wallpapers Folder\n"
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
        -show-icons -icon-theme Papirus \
        -mesg "Mode: $mode_label | Alt+1: All \302\267 Alt+2: Live \302\267 Alt+3: Static \302\267 Alt+4: Random" \
        -kb-custom-1 "Alt+1" \
        -kb-custom-2 "Alt+2" \
        -kb-custom-3 "Alt+3" \
        -kb-custom-4 "Alt+4" \
        -i 2>/dev/null)
    local exit_code=$?

    [ $exit_code -ge 10 ] && [ $exit_code -le 13 ] && {
        local new_mode
        case $exit_code in
            10) new_mode="all" ;;
            11) new_mode="live" ;;
            12) new_mode="static" ;;
            13) random_wallpaper ; return ;;
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
        *"\342\200\224\342\200\224\342\200\224"*)
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
    for f in "$LIVE_DIR"/*.mp4; do
        [ -f "$f" ] && files+=("$f")
    done
    for f in "$STATIC_DIR"/*.{png,jpg,jpeg}; do
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
        *.mp4)
            "$SCRIPT_DIR/wallpaperctl.sh" stop 2>/dev/null
            name=$(basename "$file" .mp4)
            mpvpaper -f -l bottom -o "--input-ipc-server=$IPC_SOCKET no-audio loop" "$MONITOR" "$file"
            notify-send "Wallpaper" "Live: $name"
            ;;
        *.png|*.jpg|*.jpeg)
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
```

### 3. `~/.config/hypr/Scripts/wallpaper.rasi`

```rasi
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
```

### 4. `~/.config/hypr/Scripts/wallpaper-watcher.sh`

```bash
#!/bin/bash

LIVE_DIR="$HOME/Pictures/Live wall"
STATIC_DIR="$HOME/Pictures/Wallpapers"
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
```

### 5. `~/.config/systemd/user/wallpaper-watcher.service`

```ini
[Unit]
Description=Wallpaper directory watcher - detects new files automatically
After=graphical-session.target

[Service]
ExecStart=%h/.config/hypr/Scripts/wallpaper-watcher.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

## Setup Steps

### 1. Create directories and put wallpaper files

```bash
mkdir -p ~/Pictures/"Live wall"
mkdir -p ~/Pictures/Wallpapers
mkdir -p ~/.config/hypr/Scripts
mkdir -p ~/.config/systemd/user
```

Place `.mp4`/`.webm` files in `~/Pictures/Live wall/` and `.png`/`.jpg`/`.jpeg` files in `~/Pictures/Wallpapers/`.

### 2. Create the script files

Copy all script files into `~/.config/hypr/Scripts/`. Make them executable:

```bash
chmod +x ~/.config/hypr/Scripts/wallpaperctl.sh
chmod +x ~/.config/hypr/Scripts/wallpaper-picker.sh
chmod +x ~/.config/hypr/Scripts/wallpaper-watcher.sh
```

### 3. Add keybinds to `~/.config/hypr/keybinds.conf`

```conf
# Wallpaper Controls
bind = SUPER, V, exec, ~/.config/hypr/Scripts/wallpaperctl.sh toggle      #"Wallpaper Toggle"
bind = SUPER SHIFT, V, exec, ~/.config/hypr/Scripts/wallpaperctl.sh live   #"Wallpaper Live"
bind = SUPER, P, exec, ~/.config/hypr/Scripts/wallpaperctl.sh static       #"Wallpaper Static"
bind = SUPER SHIFT, P, exec, ~/.config/hypr/Scripts/wallpaper-picker.sh    #"Wallpaper Picker"
```

### 4. (Optional) Enable wallpaper folder watcher

The wallpaper watcher automatically detects new files added to your wallpaper folders and notifies you.

```bash
systemctl --user daemon-reload
systemctl --user enable --now wallpaper-watcher.service
```

### 5. (Optional) Auto-start live wallpaper on login

Add to `~/.config/hypr/startup.conf`:

```conf
# Live wallpaper (uses mpvpaper)
exec-once = $HOME/.config/hypr/Scripts/wallpaperctl.sh live
```

### 6. Reload Hyprland

```bash
hyprctl reload
```

## Usage

| Key | Action |
|-----|--------|
| `SUPER + V` | Toggle pause/resume live wallpaper |
| `SUPER + SHIFT + V` | Cycle to next live wallpaper |
| `SUPER + P` | Cycle to next static wallpaper |
| `SUPER + SHIFT + P` | Open Rofi wallpaper picker with thumbnails |
| (background) | Wallpaper watcher auto-detects new files via inotify |

### In the Picker

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate |
| `Enter` | Select wallpaper |
| `Alt+1` | Show all wallpapers |
| `Alt+2` | Show live wallpaper only |
| `Alt+3` | Show static wallpapers only |
| `Alt+4` | Set random wallpaper |
| `Alt+5` | Refresh wallpaper list (re-scan directories) |
| `Escape` | Exit picker |

The picker shows actual thumbnail previews next to each entry (auto-generated by `ffmpegthumbnailer` for videos and `glycin-thumbnailer` for images). The `●` marker indicates the currently active wallpaper.

### Menu Options

| Option | Action |
|--------|--------|
| `Clear Wallpaper` | Stop wallpaper and clear screen |
| `Random Wallpaper` | Pick a random wallpaper from all folders |
| `Open Wallpapers Folder` | Open the Live wall folder in Thunar |
| `Set as Default` | Save the currently active wallpaper for auto-start on login |
| `Change Folders` | Pick different wallpaper directories via GUI dialog |
| `Refresh` | Re-scan wallpaper directories (useful if new files just added) |

## Default Wallpaper

Use **Set as Default** in the picker to save the currently active wallpaper.  
It gets applied automatically on next login via `wallpaperctl.sh default` in startup.conf.

## Waybar Module (Optional)

If you use [Waybar](https://github.com/Alexays/Waybar), a wallpaper status module is included:

```
~/.config/hypr/Scripts/
└── wallpaper-waybar.sh      # Status script (JSON output for waybar custom module)

~/.config/waybar/
├── config.jsonc              # Waybar config with wallpaper module
└── style.css                # Dark theme matching the noctalia palette
```

The installer will ask if you want to set it up — or install manually:

```bash
cp wallpaper-waybar.sh ~/.config/hypr/Scripts/
chmod +x ~/.config/hypr/Scripts/wallpaper-waybar.sh
cp waybar-config.jsonc ~/.config/waybar/config.jsonc
cp waybar-style.css ~/.config/waybar/style.css
```

Then add `exec-once = waybar` to your `~/.config/hypr/startup.conf`.

### Features

| Action | Result |
|--------|--------|
| **Left click** | Opens the Rofi wallpaper picker |
| **Scroll up** | Cycles to next live wallpaper |
| **Scroll down** | Cycles to next static wallpaper |
| **Middle click** | Toggles pause/resume (live wallpapers only) |

### Status Indicators

| Icon | Meaning |
|------|---------|
| `󰎁 name` | Live wallpaper playing |
| `󰋩 name` | Static wallpaper active |
| `󰱟 none` | No wallpaper set |

## Noctalia-shell Plugin (Optional)

If you use [Noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) (Quickshell-based desktop shell), a wallpaper status bar widget is included:

```
noctalia-plugin/wallpaper-duality/
├── manifest.json
├── Main.qml
├── BarWidget.qml
└── Settings.qml
```

The installer will ask if you want to set it up — or install manually:

```bash
mkdir -p ~/.config/noctalia/plugins/wallpaper-duality
cp noctalia-plugin/wallpaper-duality/* ~/.config/noctalia/plugins/wallpaper-duality/
```

Then add to `~/.config/noctalia/plugins.json`:

```json
"wallpaper-duality": {
    "enabled": true,
    "sourceUrl": "https://github.com/koko84749/wallpaper-duality"
}
```

And add `"plugin:wallpaper-duality"` to your bar widgets in `~/.config/noctalia/settings.json` under `bar.widgets.right`. Restart noctalia-shell with `qs -c noctalia-shell`.

### Features

| Action | Result |
|--------|--------|
| **Left click** | Opens the Rofi wallpaper picker |
| **Right click** | Context menu (Random, Toggle pause, Settings) |
| **Scroll up** | Cycles to next live wallpaper |
| **Scroll down** | Cycles to next static wallpaper |

### Status Indicators

| Text | Meaning |
|------|---------|
| `󰎁 name` | Live wallpaper playing |
| `󰋩 name` | Static wallpaper active |
| `󰱟 none` | No wallpaper set |

## Notes

- Paths are now stored in `~/.config/hypr/Scripts/wallpaper-config.sh` (shared by all scripts)
- Use **Change Folders** in the picker or edit `wallpaper-config.sh` directly to change directories
- Change `MONITOR` in `wallpaper-config.sh` to match your display (find yours with `hyprctl monitors`)
- The Nerd Font icons require a Nerd Font installed — change `font` in the rasi file if using a different one
- Thumbnails are cached in `~/.cache/thumbnails/` and generated on first use (may be slow initially)
- The `toggle` keybind pauses/resumes the mpv video — useful for resource saving
- The wallpaper watcher (`wallpaper-watcher.sh`) runs as a systemd user service and sends a notification when new video/image files are added to either directory
- Use `systemctl --user status wallpaper-watcher.service` to check if the watcher is running
- The picker always reads directories fresh — no cache to clear. The `Refresh` option simply re-opens the picker
