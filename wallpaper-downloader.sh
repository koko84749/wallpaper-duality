#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/wallpaper-config.sh"

TMP_DIR="/tmp/wallpaper-downloader"
RESULTS_FILE="$TMP_DIR/results.txt"
THUMB_DIR="$TMP_DIR/thumbs"
mkdir -p "$THUMB_DIR"

ICON_LIVE="\xEE\x80\x8E"
ICON_STATIC="\xEE\x80\x89"
ICON_MAG="\xEF\x80\x82"
ICON_CODE="\xEF\x84\xA1"
ICON_CATEGORY="\xEF\x81\xB4"

# ─── HELPERS ───

urlencode() {
    local s="$1" i c
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            ' ') printf '%%20' ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

sanitize_filename() {
    echo "$1" | sed 's/[\/:*?"<>|]/_/g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

fetch_json() {
    curl -sL --max-time 15 -H "User-Agent: wallpaper-duality/2.0" "$1"
}

fetch_page() {
    curl -sL --max-time 15 \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        "$1"
}

prompt_for_key() {
    local var_name="$1" display_name="$2" signup_url="$3"
    if [ -z "${!var_name}" ]; then
        local key
        key=$(zenity --entry --title="$display_name API Key" \
            --text="Enter your $display_name API key\n\nGet one at: $signup_url" 2>/dev/null)
        if [ -n "$key" ]; then
            local escaped
            escaped=$(printf '%s\n' "$key" | sed 's/[\/&]/\\&/g')
            sed -i "s/^$var_name=.*/$var_name=\"$escaped\"/" "$SCRIPT_DIR/wallpaper-config.sh"
            source "$SCRIPT_DIR/wallpaper-config.sh"
        fi
    fi
    if [ -z "${!var_name}" ]; then
        notify-send "Wallpaper Downloader" "No $display_name API key configured" -u critical
        return 1
    fi
}

download_file() {
    local url="$1" dest="$2"
    if command -v curl &>/dev/null; then
        curl -sL --max-time 30 -o "$dest" "$url"
    else
        wget -q -O "$dest" "$url"
    fi
}

fetch_thumb() {
    local url="$1" dest="$2"
    [ -f "$dest" ] && return 0
    download_file "$url" "$dest"
}

show_results_menu() {
    local source_type="$1"
    local dest_dir="$2"
    local items=() thumbs=() titles=()
    local global_idx=0
    local IFS=$'\n'

    while IFS='|' read -r title url thumb_url filename; do
        [ -z "$title" ] && continue
        titles+=("$title")
        items+=("$title")
        local thumb_file="$THUMB_DIR/thumb_${global_idx}"
        thumbs+=("$thumb_file")
        fetch_thumb "$thumb_url" "$thumb_file" &
        global_idx=$((global_idx + 1))
    done < "$RESULTS_FILE"
    wait

    local chosen exit_code
    chosen=$(for (( i=0; i<${#items[@]}; i++ )); do
        printf "%s\\0icon\\x1fthumbnail://%s\n" "${items[$i]}" "${thumbs[$i]}"
    done | rofi -dmenu -p "Download" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" \
        -show-icons -i 2>/dev/null)
    exit_code=$?

    [ $exit_code -ne 0 ] && return 1
    [ -z "$chosen" ] && return 1

    local i
    for (( i=0; i<${#titles[@]}; i++ )); do
        if [ "${items[$i]}" = "$chosen" ]; then
            local IFS='|'
            read -r title url thumb_url filename <<< "$(sed -n "$((i+1))p" "$RESULTS_FILE")"
            notify-send "Wallpaper Downloader" "Downloading: $title..." -t 3000
            download_file "$url" "$dest_dir/$filename"
            if [ $? -eq 0 ]; then
                notify-send "Wallpaper Downloader" "Downloaded: $filename" -t 5000
                return 0
            else
                notify-send "Wallpaper Downloader" "Download failed: $title" -u critical
                return 1
            fi
        fi
    done
    return 1
}

prompt_search_mode() {
    local source_name="$1"
    local supports_code="$2"
    local supports_category="$3"

    local options=("Search by keyword")
    [ "$supports_code" = "yes" ] && options+=("Search by ID/Code")
    [ "$supports_category" = "yes" ] && options+=("Browse categories")

    local chosen
    chosen=$(printf "%s\n" "${options[@]}" | rofi -dmenu -p "$source_name" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
    echo "$chosen"
}

prompt_input() {
    local prompt="$1"
    zenity --entry --title="$prompt" --text="Enter search term:" 2>/dev/null
}

# ─── SOURCE: U N S P L A S H ───

UNSPLASH_API="https://api.unsplash.com"

unsplash_check_config() {
    prompt_for_key "UNSPLASH_ACCESS_KEY" "Unsplash" "https://unsplash.com/developers"
}

unsplash_search() {
    local query="$1" encoded
    encoded=$(urlencode "$query")
    local url="$UNSPLASH_API/search/photos?query=$encoded&per_page=20&client_id=$UNSPLASH_ACCESS_KEY"
    local json
    json=$(fetch_json "$url")

    local count
    count=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null)
    [ -z "$count" ] || [ "$count" = "0" ] && notify-send "Unsplash" "No results found" && return 1

    > "$RESULTS_FILE"
    echo "$json" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
for r in d.get('results', []):
    pid = r['id']
    title = r.get('alt_description', '') or r.get('description', '') or pid
    title = re.sub(r'[^\w\s-]', '', title)[:60]
    url = r['urls']['raw']
    thumb = r['urls']['thumb']
    ext = 'jpg'
    fname = f'{pid}_{title}.{ext}'.replace(' ', '_')
    fname = re.sub(r'[^a-zA-Z0-9._-]', '', fname)
    print(f'{title}|{url}|{thumb}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    [ ! -s "$RESULTS_FILE" ] && notify-send "Unsplash" "No results found" && return 1
    show_results_menu "image" "$STATIC_DIR"
}

unsplash_by_code() {
    local code="$1"
    local json
    json=$(fetch_json "$UNSPLASH_API/photos/$code?client_id=$UNSPLASH_ACCESS_KEY")

    local pid title url thumb ext fname
    pid=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    [ -z "$pid" ] && notify-send "Unsplash" "Invalid ID: $code" -u critical && return 1

    > "$RESULTS_FILE"
    echo "$json" | python3 -c "
import sys, json, re
r = json.load(sys.stdin)
title = r.get('alt_description', '') or r.get('description', '') or r['id']
title = re.sub(r'[^\w\s-]', '', title)[:60]
url = r['urls']['raw']
thumb = r['urls']['thumb']
ext = 'jpg'
fname = f\"{r['id']}_{title}.{ext}\".replace(' ', '_')
fname = re.sub(r'[^a-zA-Z0-9._-]', '', fname)
print(f'{title}|{url}|{thumb}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    show_results_menu "image" "$STATIC_DIR"
}

# ─── SOURCE: W A L L H A V E N ───

WALLHAVEN_API="https://wallhaven.cc/api/v1"

wallhaven_check_config() {
    prompt_for_key "WALLHAVEN_API_KEY" "Wallhaven" "https://wallhaven.cc/settings/account"
}

wallhaven_search() {
    local query="$1" encoded
    encoded=$(urlencode "$query")
    local url="$WALLHAVEN_API/search?q=$encoded&apikey=$WALLHAVEN_API_KEY&ratios=16x9&atleast=1920x1080&page=1"
    local json
    json=$(fetch_json "$url")

    local count
    count=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('meta',{}).get('total',0))" 2>/dev/null)
    [ -z "$count" ] || [ "$count" = "0" ] && notify-send "Wallhaven" "No results found" && return 1

    > "$RESULTS_FILE"
    echo "$json" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
for r in d.get('data', []):
    wid = r['id']
    tags = [t['name'] for t in r.get('tags', [])]
    title = ' '.join(tags[:3]) if tags else wid
    title = re.sub(r'[^\w\s-]', '', title)[:60]
    url = r['path']
    thumb = r['thumbs']['small']
    ext = url.split('.')[-1].split('?')[0] if '.' in url else 'jpg'
    fname = f'{wid}_{title}.{ext}'.replace(' ', '_')
    fname = re.sub(r'[^a-zA-Z0-9._-]', '', fname)
    print(f'{title}|{url}|{thumb}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    [ ! -s "$RESULTS_FILE" ] && notify-send "Wallhaven" "No results found" && return 1
    show_results_menu "image" "$STATIC_DIR"
}

wallhaven_by_code() {
    local code="$1"
    local json
    json=$(fetch_json "$WALLHAVEN_API/wallpaper/$code?apikey=$WALLHAVEN_API_KEY")

    local wid
    wid=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
    [ -z "$wid" ] && notify-send "Wallhaven" "Invalid ID: $code" -u critical && return 1

    > "$RESULTS_FILE"
    echo "$json" | python3 -c "
import sys, json, re
r = json.load(sys.stdin)['data']
tags = [t['name'] for t in r.get('tags', [])]
title = ' '.join(tags[:3]) if tags else r['id']
title = re.sub(r'[^\w\s-]', '', title)[:60]
url = r['path']
thumb = r['thumbs']['small']
ext = url.split('.')[-1].split('?')[0] if '.' in url else 'jpg'
fname = f\"{r['id']}_{title}.{ext}\".replace(' ', '_')
fname = re.sub(r'[^a-zA-Z0-9._-]', '', fname)
print(f'{title}|{url}|{thumb}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    show_results_menu "image" "$STATIC_DIR"
}

# ─── SOURCE: W A L L S F L O W ───

WALLSFLOW_URL="https://wallsflow.com"

wallsflow_search() {
    local query="$1" encoded
    encoded=$(urlencode "$query")
    local url="$WALLSFLOW_URL/index.php?do=search&subaction=search&search_start=0&full_search=0&story=$encoded"
    local html
    html=$(fetch_page "$url")

    > "$RESULTS_FILE"
    echo "$html" | python3 -c "
import sys, re
html = sys.stdin.read()
cards = re.findall(
    r'data-video-src=\"([^\"]+)\"[^>]*>.*?<img src=\"([^\"]+cloud\.wallsflow\.com/posts/[^\"]+\.webp)\"[^>]*alt=\"([^\"]+)\"',
    html, re.DOTALL)
seen = set()
for video_url, thumb_url, alt in cards:
    if video_url in seen:
        continue
    seen.add(video_url)
    fname = video_url.split('/')[-1]
    title = alt.replace(' live wallpaper for desktop', '').replace(' live wallpaper', '')
    title = re.sub(r'[^\w\s-]', '', title).strip()[:60]
    if not title:
        title = fname.rsplit('.', 1)[0][:60]
    print(f'{title}|{video_url}|{thumb_url}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    [ ! -s "$RESULTS_FILE" ] && notify-send "Wallsflow" "No results found" && return 1

    local items=() thumbs=() titles=() video_urls=() filenames=()
    local IFS=$'\n'
    local idx=0
    while IFS='|' read -r title url thumb_url filename; do
        [ -z "$title" ] && continue
        items+=("$title")
        titles+=("$title")
        video_urls+=("$url")
        filenames+=("$filename")
        local thumb_file="$THUMB_DIR/wf_${idx}"
        thumbs+=("$thumb_file")
        fetch_thumb "$thumb_url" "$thumb_file" &
        idx=$((idx + 1))
    done < "$RESULTS_FILE"
    wait

    local chosen
    chosen=$(for (( i=0; i<${#items[@]}; i++ )); do
        printf "%s\\0icon\\x1fthumbnail://%s\n" "${items[$i]}" "${thumbs[$i]}"
    done | rofi -dmenu -p "Download" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" \
        -show-icons -i 2>/dev/null)
    [ -z "$chosen" ] && return 1

    for (( i=0; i<${#titles[@]}; i++ )); do
        if [ "${items[$i]}" = "$chosen" ]; then
            notify-send "Wallpaper Downloader" "Downloading: ${titles[$i]}..." -t 3000
            download_file "${video_urls[$i]}" "$LIVE_DIR/${filenames[$i]}"
            if [ $? -eq 0 ]; then
                notify-send "Wallpaper Downloader" "Downloaded: ${filenames[$i]}" -t 5000
                return 0
            else
                notify-send "Wallpaper Downloader" "Download failed" -u critical
                return 1
            fi
        fi
    done
}

WALLSFLOW_CATEGORIES=(
    "anime|Anime"
    "games|Games"
    "superhero|Superhero"
    "nature|Nature"
    "car|Car"
    "tv|TV & Movie"
    "holiday|Holiday"
    "animal|Animal"
    "fantasy|Fantasy"
    "space|Space"
    "horror|Horror"
    "technology|Technology"
    "football|Football"
    "japan|Japan"
)

wallsflow_browse() {
    local cat_menu=()
    for entry in "${WALLSFLOW_CATEGORIES[@]}"; do
        cat_menu+=("${entry#*|}")
    done

    local chosen
    chosen=$(printf "%s\n" "${cat_menu[@]}" | rofi -dmenu -p "Wallsflow Category" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
    [ -z "$chosen" ] && return 1

    local tag=""
    for entry in "${WALLSFLOW_CATEGORIES[@]}"; do
        if [ "${entry#*|}" = "$chosen" ]; then
            tag="${entry%%|*}"
            break
        fi
    done
    [ -z "$tag" ] && return 1

    local html
    html=$(fetch_page "$WALLSFLOW_URL/tag/$tag/")

    > "$RESULTS_FILE"
    echo "$html" | python3 -c "
import sys, re
html = sys.stdin.read()
cards = re.findall(
    r'data-video-src=\"([^\"]+)\"[^>]*>.*?<img src=\"([^\"]+cloud\.wallsflow\.com/posts/[^\"]+\.webp)\"[^>]*alt=\"([^\"]+)\"',
    html, re.DOTALL)
seen = set()
for video_url, thumb_url, alt in cards:
    if video_url in seen:
        continue
    seen.add(video_url)
    fname = video_url.split('/')[-1]
    title = alt.replace(' live wallpaper for desktop', '').replace(' live wallpaper', '')
    title = re.sub(r'[^\w\s-]', '', title).strip()[:60]
    if not title:
        title = fname.rsplit('.', 1)[0][:60]
    print(f'{title}|{video_url}|{thumb_url}|{fname}')
" 2>/dev/null >> "$RESULTS_FILE"

    [ ! -s "$RESULTS_FILE" ] && notify-send "Wallsflow" "No wallpapers in $chosen" && return 1

    local items=() thumbs=() titles=() video_urls=() filenames=()
    local IFS=$'\n'
    local idx=0
    while IFS='|' read -r title url thumb_url filename; do
        [ -z "$title" ] && continue
        items+=("$title")
        titles+=("$title")
        video_urls+=("$url")
        filenames+=("$filename")
        local thumb_file="$THUMB_DIR/wfc_${idx}"
        thumbs+=("$thumb_file")
        fetch_thumb "$thumb_url" "$thumb_file" &
        idx=$((idx + 1))
    done < "$RESULTS_FILE"
    wait

    chosen=$(for (( i=0; i<${#items[@]}; i++ )); do
        printf "%s\\0icon\\x1fthumbnail://%s\n" "${items[$i]}" "${thumbs[$i]}"
    done | rofi -dmenu -p "Download" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" \
        -show-icons -i 2>/dev/null)
    [ -z "$chosen" ] && return 1

    for (( i=0; i<${#titles[@]}; i++ )); do
        if [ "${items[$i]}" = "$chosen" ]; then
            notify-send "Wallpaper Downloader" "Downloading: ${titles[$i]}..." -t 3000
            download_file "${video_urls[$i]}" "$LIVE_DIR/${filenames[$i]}"
            if [ $? -eq 0 ]; then
                notify-send "Wallpaper Downloader" "Downloaded: ${filenames[$i]}" -t 5000
                return 0
            else
                notify-send "Wallpaper Downloader" "Download failed" -u critical
                return 1
            fi
        fi
    done
}

# ─── MAIN ───

source_menu() {
    local sources=(
        "Wallsflow (Live)"
        "Unsplash (Static)"
        "Wallhaven (Static)"
    )

    local chosen
    chosen=$(printf "%s\n" "${sources[@]}" | rofi -dmenu -p "Download Source" \
        -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
    [ -z "$chosen" ] && exit 0

    case "$chosen" in
        "Wallsflow (Live)")
            local actions=("Search by keyword" "Browse categories")
            local action
            action=$(printf "%s\n" "${actions[@]}" | rofi -dmenu -p "Wallsflow" \
                -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
            [ -z "$action" ] && source_menu
            case "$action" in
                "Search by keyword")
                    local query
                    query=$(prompt_input "Search Wallsflow")
                    [ -z "$query" ] && source_menu
                    wallsflow_search "$query" ;;
                "Browse categories")
                    wallsflow_browse ;;
            esac
            [ $? -ne 0 ] && sleep 2 && source_menu
            exit 0
            ;;
        "Unsplash (Static)")
            unsplash_check_config || exit 1
            local actions=("Search by keyword" "Search by photo ID")
            local action
            action=$(printf "%s\n" "${actions[@]}" | rofi -dmenu -p "Unsplash" \
                -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
            [ -z "$action" ] && source_menu
            case "$action" in
                "Search by keyword")
                    local query
                    query=$(prompt_input "Search Unsplash")
                    [ -z "$query" ] && source_menu
                    unsplash_search "$query" ;;
                "Search by photo ID")
                    local code
                    code=$(prompt_input "Unsplash Photo ID")
                    [ -z "$code" ] && source_menu
                    unsplash_by_code "$code" ;;
            esac
            [ $? -ne 0 ] && sleep 2 && source_menu
            exit 0
            ;;
        "Wallhaven (Static)")
            wallhaven_check_config || exit 1
            local actions=("Search by keyword" "Search by wallpaper ID")
            local action
            action=$(printf "%s\n" "${actions[@]}" | rofi -dmenu -p "Wallhaven" \
                -theme "$SCRIPT_DIR/wallpaper.rasi" -i 2>/dev/null)
            [ -z "$action" ] && source_menu
            case "$action" in
                "Search by keyword")
                    local query
                    query=$(prompt_input "Search Wallhaven")
                    [ -z "$query" ] && source_menu
                    wallhaven_search "$query" ;;
                "Search by wallpaper ID")
                    local code
                    code=$(prompt_input "Wallhaven Wallpaper ID")
                    [ -z "$code" ] && source_menu
                    wallhaven_by_code "$code" ;;
            esac
            [ $? -ne 0 ] && sleep 2 && source_menu
            exit 0
            ;;
    esac
}

source_menu
