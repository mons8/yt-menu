#!/bin/bash

# --- CONSTANTS & CONFIGURATION ---
set -o pipefail

# Colors
NC='\e[0m'
## Standard UI Colors
GREEN='\e[0;32m'
B_WHITE='\e[1;37m'
YELLOW='\e[0;33m'
B_BLUE='\e[1;34m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
RED='\e[0;31m'
## Palette for Category rotation
COLORS=('\e[0;32m' '\e[1;34m' '\e[1;36m' '\e[0;33m' '\e[1;33m' '\e[0;35m' '\e[1;35m' '\e[0;31m' '\e[1;37m')

# Paths
PROMPT_DIR="$(dirname "$0")/../prompts"
CONFIG_DIR="$(dirname "$0")/../config"
MAIN_CONFIG="$CONFIG_DIR/llm-package.cfg"
STATE_FILE="$CONFIG_DIR/PromptSelection.state"
CUSTOM_TEXT_FILE="$CONFIG_DIR/CustomPrompt.state"

# --- DATA STRUCTURES ---
declare -a menu_items
declare -a silent_includes
declare -A selected_indices # map: index -> 1
declare -A assigned_hotkeys # map: char -> 1 (collision detection)
declare -A category_selections # map: cat_name -> selected_index (for 'single' type enforcement)
custom_prompt_text=""
opt_no_sticky=false
comments_basedir=""
# Global flag to track if transcription was created
TRANSCRIPTION_WAS_SKIPPED=false

# --- LIBRARY & PRE-FLIGHT ---
if ! command -v jq &> /dev/null; then echo "[yt-menu] Error: 'jq' command not found." >&2; exit 1; fi
if ! command -v realpath &> /dev/null; then echo "[yt-menu] Error: 'realpath' command not found." >&2; exit 1; fi
if [ ! -d "$PROMPT_DIR" ]; then echo "[yt-menu] Error: Prompt directory not found at '$PROMPT_DIR'." >&2; exit 1; fi

source "$(dirname "$0")/../lib/environment.sh"

# --- DATA STRUCTURES ---
# menu_items stores: "hotkey|cat_name|item_name|file_path|json_key|select_type|special_flag|color_code"
declare -a menu_items
declare -a silent_includes
declare -A selected_indices # map: index -> 1
declare -A assigned_hotkeys # map: char -> 1 (collision detection)
declare -A category_selections # map: cat_name -> selected_index (for 'single' type enforcement)
custom_prompt_text=""

# --- FUNCTIONS ---

# Saves Promt State
save_prompt_state() {
    # If sticky prompts are disabled, clear state files and return
    if [ "$opt_no_sticky" = true ]; then
        > "$STATE_FILE"
        > "$CUSTOM_TEXT_FILE"
        return
    fi

    # 1. Save Selections (Category|ItemName)
    : > "$STATE_FILE" # truncate
    if [ "$omit_comments" = true ]; then echo "SPECIAL|OMIT_COMMENTS" >> "$STATE_FILE"; fi

    for i in "${!selected_indices[@]}"; do
        IFS='|' read -r _ cat item _ _ _ _ _ <<< "${menu_items[$i]}"
        echo "${cat}|${item}" >> "$STATE_FILE"
    done

    # 2. Save Custom Prompt Text
    echo -n "$custom_prompt_text" > "$CUSTOM_TEXT_FILE"
}

# Loads Promt State
load_prompt_state() {
    # 1. Load Custom Prompt Text
    if [ -f "$CUSTOM_TEXT_FILE" ]; then
        custom_prompt_text=$(<"$CUSTOM_TEXT_FILE")
    fi

    # 2. Load Selections
    if [ -f "$STATE_FILE" ]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Handle Omit Flag
            if [[ "$line" == "SPECIAL|OMIT_COMMENTS" ]]; then
                omit_comments=true
                continue
            fi

            local stored_cat="${line%%|*}"
            local stored_item="${line#*|}"

            # Find matching index in menu_items
            for i in "${!menu_items[@]}"; do
                IFS='|' read -r _ cat item _ _ select_type _ _ <<< "${menu_items[$i]}"
                if [[ "$cat" == "$stored_cat" && "$item" == "$stored_item" ]]; then
                    selected_indices[$i]=1
                    # Enforce single selection logic tracking
                    if [[ "$select_type" == "single" ]]; then
                        category_selections[$cat]=$i
                    fi
                    break
                fi
            done
        done < "$STATE_FILE"
    fi
}

# Re-writes the config file with current values
update_config_file() {
    echo "BASE_DIR=\"$comments_basedir\"" > "$MAIN_CONFIG"
    echo "OPT_NO_STICKY=\"$opt_no_sticky\"" >> "$MAIN_CONFIG"
}

# Determines the color based on the directory number prefix
get_category_color() {
    local num_part=$1
    # Strip leading zeros, handle 10 base to avoid octal interpretation
    local idx=$(( 10#$num_part % ${#COLORS[@]} ))
    echo "${COLORS[$idx]}"
}

# Generates a smart mnemonic hotkey
generate_hotkey() {
    local name="$1"
    local index=$2
    local key=""

    # 1. First 9 items get numbers
    if [ "$index" -lt 9 ]; then
        key="$((index + 1))"
        if [[ -z "${assigned_hotkeys[$key]}" ]]; then
            echo "$key"; return
        fi
    fi

    # 2. Try Initials (First letter of first word, first letter of second word, etc)
    # Remove non-alphanumeric, split by space
    local clean_name="${name//[^a-zA-Z0-9 ]/}"
    read -ra words <<< "$clean_name"
    
    # Attempt first letters of words
    for word in "${words[@]}"; do
        local char="${word:0:1}"
        char="${char,,}" # lowercase
        if [[ -z "${assigned_hotkeys[$char]}" && "$char" =~ [a-z] ]]; then
            echo "$char"; return
        fi
    done

    # 3. Scan through the string for any available character
    for (( i=0; i<${#clean_name}; i++ )); do
        local char="${clean_name:$i:1}"
        char="${char,,}"
        if [[ "$char" =~ [a-z] ]] && [[ -z "${assigned_hotkeys[$char]}" ]]; then
            echo "$char"; return
        fi
    done

    # 4. Fallback: Find first unused letter a-z
    for char in {a..z}; do
        if [[ -z "${assigned_hotkeys[$char]}" ]]; then
            echo "$char"; return
        fi
    done
    
    # 5. Last resort: random uppercase (unlikely to reach here)
    echo "X"
}

# Recursively scans prompts directory
# Recursively scans prompts directory
load_menu_items() {
    menu_items=()
    silent_includes=()
    assigned_hotkeys=()

    # --- RESRVE STATIC HOTKEYS ---
    # Pre-assign keys used for hardcoded menu options to prevent
    # the dynamic generator from assigning them to prompt files.
    assigned_hotkeys["o"]=1  # Reserved for Omit
    assigned_hotkeys["d"]=1  # Reserved for Disable Sticky

    # Loop through Category Directories
    while IFS= read -r cat_dir; do
        local cat_dirname=$(basename "$cat_dir")
        local cat_num="${cat_dirname%%-*}"
        local cat_name_raw="${cat_dirname#*-}"
        local cat_name="${cat_name_raw//_/ }"

        # Check for 00- prefix (Silent/Global)
        if [[ "$cat_num" == "00" ]]; then
            # Load global silent includes
            if [ -f "$cat_dir/category.json" ]; then
                local global_key=$(jq -r '.key // "global"' "$cat_dir/category.json")
                while IFS= read -r file; do
                    local content=$(<"$file")
                    # Store as json object string
                    silent_includes+=("$(jq -n --arg k "$global_key" --arg v "$content" '{key: $k, value: $v}')")
                done < <(find "$cat_dir" -type f ! -name "category.json" ! -name ".*" | sort)
            fi
            continue
        fi

        # Load Category Config
        local config_file="$cat_dir/category.json"
        local json_key="misc"
        local select_type="multi"
        local special_flag="none"

        if [ -f "$config_file" ]; then
            json_key=$(jq -r '.key // "misc"' "$config_file")
            select_type=$(jq -r '.type // "multi"' "$config_file")
            special_flag=$(jq -r '.special // "none"' "$config_file")
        fi

        local cat_color=$(get_category_color "$cat_num")

        # Loop through Items in Category
        while IFS= read -r file; do
            local item_filename=$(basename "$file")
            # If item filename starts with digits and -, strip it for display, otherwise keep it
            local item_name_clean="${item_filename%.*}" # remove extension
            item_name_clean="${item_name_clean//_/ }"

            # Smart Hotkey
            local current_total=${#menu_items[@]}
            # This function now checks assigned_hotkeys, which already contains 'o' and 'd'
            local hotkey=$(generate_hotkey "$item_name_clean" "$current_total")
            assigned_hotkeys["$hotkey"]=1

            # Store absolute path
            local file_path=$(realpath "$file")

            # Format: hotkey|cat_name|item_name|file_path|json_key|select_type|special_flag|color_code
            menu_items+=("$hotkey|$cat_name|$item_name_clean|$file_path|$json_key|$select_type|$special_flag|$cat_color")

        done < <(find "$cat_dir" -type f ! -name "category.json" ! -name ".*" | sort)

    done < <(find "$PROMPT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

display_menu() {
    clear
    echo -e "\n${B_WHITE}--- Prompt Injection ---${NC}\n"
    echo -e "Edit the menu and prompts dynamically by changing folder names, filenames and contents in ../yt-menu/prompts/\n"

    # 1. Print Selections
    echo -e "${YELLOW}Current Selections:${NC}"
    local has_selections=false
    local sorted_indices=$(for i in "${!selected_indices[@]}"; do echo "$i"; done | sort -n)

    for i in $sorted_indices; do
        IFS='|' read -r _ cat item _ _ _ special color <<< "${menu_items[$i]}"
        echo -e "  ${color}${cat}:${NC} $item"
        # Show preview of custom text if active
        if [[ "$special" == "interactive" ]]; then
            # Truncate for display if too long
            local preview="${custom_prompt_text%%$'\n'*}"
            if [ ${#preview} -gt 60 ]; then preview="${preview:0:57}..."; fi
            echo -e "      ${B_WHITE}\"$preview\"${NC}"
        fi
        has_selections=true
    done
    [[ "$has_selections" == false ]] && echo "  None"
    echo ""

    # 2. Print Menu Options
    for i in "${!menu_items[@]}"; do
        IFS='|' read -r hotkey cat item _ _ _ special color <<< "${menu_items[$i]}"
        local status="[ ]"
        [[ -v "selected_indices[$i]" ]] && status="[${GREEN}x${NC}]"
        printf " %s %b ${color}[%-8s]${NC} | %s\n" "$hotkey." "$status" "$cat" "$item"
    done

    # Global Options
    local omit_status="[ ]"
    [[ "$omit_comments" == true ]] && omit_status="[${GREEN}x${NC}]"

    local sticky_status="[ ]"
    [[ "$opt_no_sticky" == true ]] && sticky_status="[${GREEN}x${NC}]"

    echo ""
    printf " %s %b %b\n" "o." "$omit_status" "${B_WHITE}Omit downloading comments.${NC}"
    printf " %s %b %b\n" "d." "$sticky_status" "${B_WHITE}Disable Sticky Prompts.${NC}"

    echo -e "\n${B_BLUE} Enter Hotkey to toggle, or ${B_WHITE}+${B_BLUE} When Done${NC}\n"
}

# Processes the final prompt payload dynamically based on keys
assemble_prompt_payload() {
    # 1. Create a temporary array of JSON objects: [ {key: "...", value: "..."} ]
    local json_objects=()

    # Add Silent Includes (These will be processed first by jq, establishing Key priority)
    for entry in "${silent_includes[@]}"; do
        json_objects+=("$entry")
    done

    # Add User Selections (Sorted by menu index to preserve 1..9..a..z order)
    for i in $(printf '%s\n' "${!selected_indices[@]}" | sort -n); do
        IFS='|' read -r _ _ item_name file_path json_key _ special _ <<< "${menu_items[$i]}"

        local content=""
        if [[ "$special" == "interactive" && -n "$custom_prompt_text" ]]; then
            content="$custom_prompt_text"
        else
            content=$(<"$file_path")
        fi

        # Format content string
        local formatted_content=" * ${item_name}: ${content}"

        # Create tiny JSON object for this item
        local json_obj
        json_obj=$(jq -n --arg k "$json_key" --arg v "$formatted_content" '{key: $k, value: $v}')
        json_objects+=("$json_obj")
    done

    # 2. Use jq to reduce the array into a single object
    # We construct a valid JSON string manually to avoid bash array expansion issues
    local json_input="["
    local first=true
    for obj in "${json_objects[@]}"; do
        if [ "$first" = true ]; then first=false; else json_input+=","; fi
        json_input+="$obj"
    done
    json_input+="]"

    # JQ: Use reduce to preserve the order of keys as they appeared in the array
    echo "$json_input" | jq 'reduce .[] as $item ({}; .[$item.key] += [$item.value])'
}

# --- SCRIPT BODY ---

# --- 1. Load Configuration (llm-package.cfg) ---
if [ ! -d "$CONFIG_DIR" ]; then mkdir -p "$CONFIG_DIR"; fi

if [ -f "$MAIN_CONFIG" ]; then
    source "$MAIN_CONFIG"
    # Map raw vars to script vars if needed, though sourcing handles BASE_DIR and OPT_NO_STICKY
    comments_basedir="$BASE_DIR"
    opt_no_sticky="${OPT_NO_STICKY:-false}"
fi

# Ensure Download Directory Exists
if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then
        echo "[yt-menu] Config ($MAIN_CONFIG) missing or BASE_DIR not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for llm-packages: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then echo "[yt-menu] Path cannot be empty."; fi
        done
        update_config_file # Save immediately
        echo "[yt-menu] Configuration saved."
    else
        echo "[yt-menu] Error: Base directory not configured. Exit." >&2; exit 1
    fi
else
    echo -e "Using base directory: ${BLUE}$comments_basedir${NC}"
fi

# --- 2. Pre-Load Prompts & State ---
# We load items now so we can restore sticky state before the URL prompt
load_menu_items
if [ "$opt_no_sticky" = false ]; then
    load_prompt_state
fi

# --- 3. URL Input with Context ---
echo -e "\n${B_WHITE}--- Enter URL for llm-package ---${NC}\n"
echo -e "${B_BLUE}Sticky Prompts:${NC}"
has_active_prompts=false

# Display current Sticky Prompts
sorted_active_indices=$(for i in "${!selected_indices[@]}"; do echo "$i"; done | sort -n)

for i in $sorted_active_indices; do
    IFS='|' read -r _ cat item _ _ _ special color <<< "${menu_items[$i]}"
    echo -e "  ${color}${cat}:${NC} $item"
    # Display the Custom Prompt
    if [[ "$special" == "interactive" && -n "$custom_prompt_text" ]]; then local preview="$custom_prompt_text%%$'\n'*}" #Only display first line
        if [${#preview} -gt 50 ]; then preview="${preview:0:47}..."; fi
        echo -e "      ${B_WHITE}\"$preview\"${NC}"
    fi
#     If we want full Custom Prompt text. (comment above then)
#     if [[ "$special" == "interactive" && -n "$custom_prompt_text" ]]; then
#         # We print the text and use 'sed' to add 6 spaces to the start of every line
#         # so it aligns beautifully under the menu item.
#         echo -e "${B_WHITE}${custom_prompt_text}${NC}" | sed 's/^/      /'
#     fi
    has_active_prompts=true
done

if [ "$has_active_prompts" = false ]; then echo "  (None)"; fi
if [ "$omit_comments" = true ]; then echo -e "  ${RED}[Omit Comments]${NC}"; fi
echo ""

prompt_menu_requested=false
printf "%b" "${B_WHITE}Enter URL${NC} (Append ${B_BLUE}\"+\"${NC} to enter menu, i.e. http://url.com/url${B_BLUE}+${NC})${B_WHITE}:${NC} "
read -r url_input

if [[ "$url_input" == *+ ]]; then prompt_menu_requested=true; url="${url_input%+}"; else url="$url_input"; fi
if [ -z "$url" ]; then echo "[yt-menu] Error: URL cannot be empty." >&2; exit 1; fi

# --- 4. Interactive Menu Loop ---
if [ "$prompt_menu_requested" = true ]; then

    while true; do
        display_menu
        printf "${B_WHITE}Choice: ${NC}"
        read -r -n 1 input_char || break
        echo ""

        if [[ "$input_char" == "+" ]]; then break; fi

        # Toggle Omit
        if [[ "$input_char" == "o" || "$input_char" == "O" ]]; then
            if [[ "$omit_comments" == true ]]; then omit_comments=false; else omit_comments=true; fi
            continue
        fi

        # Toggle Sticky (Disable)
        if [[ "$input_char" == "d" || "$input_char" == "D" ]]; then
            if [[ "$opt_no_sticky" == true ]]; then opt_no_sticky=false; else opt_no_sticky=true; fi
            # Update config immediately regarding the preference
            update_config_file
            continue
        fi

        # Standard Items Logic
        target_index=-1
        for i in "${!menu_items[@]}"; do
            IFS='|' read -r hk _ _ _ _ _ _ _ <<< "${menu_items[$i]}"
            if [[ "${hk,,}" == "${input_char,,}" ]]; then target_index=$i; break; fi
        done

        if [ "$target_index" -ne -1 ]; then
            IFS='|' read -r _ cat _ _ _ select_type special _ <<< "${menu_items[$target_index]}"

            # Interactive Special Flag
            if [[ "$special" == "interactive" ]]; then
                if [[ -v "selected_indices[$target_index]" ]]; then
                    unset "selected_indices[$target_index]"
                    # Don't clear text immediately in case of accidental toggle,
                    # but maybe we should? The prompt implies state saving text.
                    # We will keep text in memory but unselect the item.
                else
                    echo -e "\n${B_WHITE}Enter custom prompt (End with 'EOF' on new line):${NC}"
                    # If previous text exists, show it (optional, but good UX)
                    if [ -n "$custom_prompt_text" ]; then echo -e "${CYAN}Current:${NC} $custom_prompt_text"; fi

                    line=""; buffer=""
                    while IFS= read -r line; do [[ "$line" == "EOF" ]] && break; buffer+="${line}"$'\n'; done

                    # Only update text if user typed something (excluding EOF).
                    # If empty, keep old text? No, assume replace.
                    if [ -n "${buffer%$'\n'}" ]; then
                         custom_prompt_text="${buffer%$'\n'}"
                    fi

                    if [[ -n "${custom_prompt_text//[[:space:]]/}" ]]; then
                        selected_indices[$target_index]=1
                    fi
                fi
            else
                # Toggle Normal Selection
                if [[ -v "selected_indices[$target_index]" ]]; then
                    unset "selected_indices[$target_index]"
                    if [[ "${category_selections[$cat]}" == "$target_index" ]]; then unset "category_selections[$cat]"; fi
                else
                    if [[ "$select_type" == "single" ]]; then
                        if [[ -v "category_selections[$cat]" ]]; then
                            old_idx="${category_selections[$cat]}"
                            unset "selected_indices[$old_idx]"
                        fi
                        category_selections[$cat]=$target_index
                    fi
                    selected_indices[$target_index]=1
                fi
            fi
        fi
    done
fi

# --- 5. Finalize State & Assemble ---
# Save state if sticky is enabled (regardless if menu was requested or not,
# though usually changes only happen in menu. But 'D' might have changed via config manually)
save_prompt_state

echo -e "\n[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Assembling dynamic LLM payload..."

# Payload assemblage using either defaults or menu choices
llm_instructions_json=$(assemble_prompt_payload)

if [ -z "$llm_instructions_json" ] || [ "$llm_instructions_json" == "{}" ]; then
    echo "[yt-menu] No instructions selected (and no global includes found)."
    llm_instructions_json=""
else
    echo "[yt-menu] Instructions assembled successfully."
fi

# --- END OF MENU ---

tmp_dir=$(mktemp -d)
cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ -n "$trap_error_suppress" ]; then return; fi
    trap_error_suppress=1

    if [ $exit_code -eq 0 ]; then
        echo "[yt-menu] -----------------------------------------------------"
        if [ "$TRANSCRIPTION_WAS_SKIPPED" = true ]; then
            echo -e "[yt-menu] ${YELLOW}Warning: No subtitles found. Package lacks transcription.${NC}"
        fi
        echo -n "[yt-menu] Cleaning up ($tmp_dir)..."
        rm -rf "$tmp_dir"
        echo " Done."
    else
        echo "[yt-menu] Error exit ($exit_code). Temp dir preserved: $tmp_dir" >&2
    fi
}
trap cleanup EXIT

# --- PHASE 1: DOWNLOAD ASSETS ---
echo "[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Phase 1: Downloading metadata & comments..."
declare -a dl_cmd=("${YTDLP_COMMAND_ARRAY[@]}" --no-playlist)
if [ "$omit_comments" = false ]; then dl_cmd+=(--extractor-args "youtube:comment_sort=top" --write-comments); fi
dl_cmd+=( --no-playlist --write-info-json --write-description --skip-download --ignore-config --paths "$tmp_dir" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url")
"${dl_cmd[@]}"
if [ $? -ne 0 ]; then echo "[yt-menu] Error: yt-dlp failed. Aborting." >&2; exit 1; fi

# Find info json
info_json_file=$(find "$tmp_dir" -name "*.info.json" | head -n 1)
if [ -z "$info_json_file" ]; then echo "[yt-menu] Error: .info.json not found." >&2; exit 1; fi
base_filename="${info_json_file%.info.json}"
description_file="$base_filename.description"

# --- PHASE 2: SUBTITLE SELECTION ---
echo "[yt-menu] Phase 2: Subtitle analysis..."
mapfile -t available_sub_langs < <(jq -r '(.subtitles // {}) + (.automatic_captions // {}) | keys[]' "$info_json_file" | sort -u)
original_lang=$(jq -r '.language // "en"' "$info_json_file")

best_lang_to_download=""
if [ ${#available_sub_langs[@]} -gt 0 ]; then
    # 1. Exact match
    for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "$original_lang" ]] && best_lang_to_download="$lang" && break; done
    # 2. Primary tag match (en from en-US)
    if [ -z "$best_lang_to_download" ] && [[ "$original_lang" == *-* ]]; then
        primary="${original_lang%%-*}"
        for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "$primary" ]] && best_lang_to_download="$lang" && break; done
    fi
    # 3. Fallback to English
    if [ -z "$best_lang_to_download" ]; then
        for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "en" ]] && best_lang_to_download="$lang" && break; done
    fi
    # 4. First available
    if [ -z "$best_lang_to_download" ]; then best_lang_to_download="${available_sub_langs[0]}"; fi

    if [ -n "$best_lang_to_download" ]; then
        echo "[yt-menu]   -> Downloading subtitle: $best_lang_to_download"
        "${YTDLP_COMMAND_ARRAY[@]}" --no-playlist --write-subs --write-auto-subs --sub-lang "$best_lang_to_download" --sub-format "srt/ass/best" --skip-download --ignore-errors --ignore-config --paths "$tmp_dir" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url"
    fi
fi

# --- METADATA PARSING ---
fname_no_path=$(basename "$base_filename")
id_and_date_part="${fname_no_path##* \[}"
channel_and_title_part="${fname_no_path%% \[*}"
video_id="${id_and_date_part%%\]*}"; upload_date="${id_and_date_part##*.}"
channel="${channel_and_title_part%% - *}"; video_title="${channel_and_title_part#* - }"
video_url="https://www.youtube.com/watch?v=${video_id}"
#  - COUNTING COMMENTS -
if [ "$omit_comments" = false ]; then
    # Count the number of items in the 'comments' array
    comment_count=$(jq -r '(.comments | length) // 0' "$info_json_file")
else
    comment_count="Omitted"
fi
# --- COMMENTS RESTRUCTURING ---
threaded_comments_file=""
if [ "$omit_comments" = false ]; then
    echo "[yt-menu] Restructuring comments..."
    python_script_path="$WORK_DIR/libexec/json-restructurer.py"
    threaded_comments_file=$("$VENV_PYTHON" "$python_script_path" "$info_json_file" 2>/dev/null)
else
    echo "[yt-menu] Skipping comments processing (Omitted by user)."
fi

# --- TRANSCRIPTION PROCESSING ---
echo "[yt-menu] Processing transcription..."
# Find best sub file (simplistic logic: matches lang, or just any srt/ass)
best_sub_file=$(find "$tmp_dir" -name "*.srt" -o -name "*.ass" | head -n 1) # Simplified for brevity, logic exists in prev script if strictly needed
structured_transcription_file=""

if [ -n "$best_sub_file" ]; then
    case "$best_sub_file" in
        *.srt) processor="$WORK_DIR/libexec/srt-processor.py" ;;
        *.ass) processor="$WORK_DIR/libexec/ass-processor.py" ;;
    esac
    if [ -n "$processor" ]; then
        structured_transcription_file=$("$VENV_PYTHON" "$processor" "$best_sub_file")
    fi
fi

if [ -z "$structured_transcription_file" ]; then TRANSCRIPTION_WAS_SKIPPED=true; fi

# --- FINAL PACKAGE ---
echo "[yt-menu] Creating final package..."
package_basename=$(basename "${base_filename}.llm-package.json")
temp_package_path="$tmp_dir/$package_basename"

jq_args=(--arg title "$video_title" --arg channel "$channel" --arg url "$url" --arg cc "$comment_count")
jq_filter='{metadata: {title: $title, channel: $channel, url: $url, comment_count: $cc}}'

# Inject Instructions (Prepend)
if [ -n "$llm_instructions_json" ]; then
    jq_args+=(--argjson inst "$llm_instructions_json")
    jq_filter='{llm_instructions: $inst} + '"$jq_filter"
fi

# Inject Description
if [ -f "$description_file" ]; then
    jq_args+=(--rawfile desc "$description_file")
    jq_filter="$jq_filter"' + {description: $desc}'
fi

# Inject Transcription
if [ -n "$structured_transcription_file" ]; then
    jq_args+=(--slurpfile trans "$structured_transcription_file")
    jq_filter="$jq_filter"' + {transcription: $trans[0]}'
fi

# Inject Comments
if [ -n "$threaded_comments_file" ]; then
    jq_args+=(--slurpfile comms "$threaded_comments_file")
    jq_filter="$jq_filter"' + {comments: $comms[0]}'
fi

# Inject Instructions (Prepend and append)
if [ -n "$llm_instructions_json" ]; then
    # We reuse the $inst variable defined in the prepend block
    jq_filter="$jq_filter"' + {llm_reminder: $inst}'
fi

jq -n "${jq_args[@]}" "$jq_filter" > "$temp_package_path"

if [ -s "$temp_package_path" ]; then
    final_dest="$comments_basedir/$package_basename"
    mv "$temp_package_path" "$final_dest"
    echo "[yt-menu] Package saved to: $final_dest"

    # Clipboard
    abs_path=$(realpath "$final_dest")
    if command -v wl-copy &> /dev/null; then echo "file://${abs_path}" | wl-copy --type text/uri-list
    elif command -v xclip &> /dev/null; then echo "file://${abs_path}" | xclip -selection clipboard -t text/uri-list
    fi
else
    echo "[yt-menu] Error: Failed to generate JSON package." >&2; exit 1
fi
