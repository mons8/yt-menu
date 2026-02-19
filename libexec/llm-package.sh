#!/bin/bash

# --- CONSTANTS & CONFIGURATION ---
set -o pipefail

# Colors
NC='\e[0m'
GREEN='\e[0;32m'
B_GREEN='\e[1;32m'
B_WHITE='\e[1;37m'
YELLOW='\e[0;33m'
B_BLUE='\e[1;34m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
RED='\e[0;31m'
B_RED='\e[1;31m'
GRAY='\e[1;30m'

# Palette for Category rotation
COLORS=('\e[0;32m' '\e[1;34m' '\e[1;36m' '\e[0;33m' '\e[1;33m' '\e[0;35m' '\e[1;35m' '\e[0;31m' '\e[1;37m')

# Paths
PROMPT_DIR="$(dirname "$0")/../prompts"
CONFIG_DIR="$(dirname "$0")/../config"
MAIN_CONFIG="$CONFIG_DIR/llm-package.cfg"
STATE_FILE="$CONFIG_DIR/PromptSelection.state"
CUSTOM_TEXT_FILE="$CONFIG_DIR/CustomPrompt.state"

# --- DATA STRUCTURES ---
declare -a menu_items
# menu_items stores: "hotkey|cat_name|item_name|file_path|json_key|select_type|special_flag|color_code"
declare -a silent_includes
declare -A selected_indices # map: index -> 1
declare -A assigned_hotkeys # map: char -> 1 (collision detection)
declare -A category_selections # map: cat_name -> selected_index (for 'single' type enforcement)
custom_prompt_text=""
opt_no_sticky=false
opt_no_save_this_run=false
opt_timer_enabled=false
opt_timer_seconds=5
omit_comments=false
comments_basedir=""
transcription_was_skipped=false
# ---
# The prompt menu options are dynamically generated from directory names and filenames in ../prompts
# ---
declare -a global_toggles=(
    "o|Omit downloading comments.|omit_comments"
    "d|Disable Sticky Prompts.|opt_no_sticky"
    "x|Don't update Sticky Prompts state from this run.|opt_no_save_this_run"
    "t|Auto-run timer.|opt_timer_enabled"
)
# global_toggles is the "firm" menu options below the prompts: [Hotkey|Description|Variable Name]
# (Changing or adding items here is sufficient to remove the hotkey from the pool of automatically assigned keys in the dynamic prompt menu.)

# --- LIBRARY & PRE-FLIGHT ---
if ! command -v jq &> /dev/null; then echo "[yt-menu] Error: 'jq' command not found." >&2; exit 1; fi
if ! command -v realpath &> /dev/null; then echo "[yt-menu] Error: 'realpath' command not found." >&2; exit 1; fi
if [ ! -d "$PROMPT_DIR" ]; then echo "[yt-menu] Error: Prompt directory not found at '$PROMPT_DIR'." >&2; exit 1; fi

source "$(dirname "$0")/../lib/environment.sh"

# --- FUNCTIONS ---

# Saves Promt State
save_prompt_state() {
    # If "forget this run" is enabled, do nothing at all.
    if [ "$opt_no_save_this_run" = true ]; then
        return
    fi

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
    echo "OPT_TIMER_ENABLED=\"$opt_timer_enabled\"" >> "$MAIN_CONFIG"
    echo "OPT_TIMER_SECONDS=\"$opt_timer_seconds\"" >> "$MAIN_CONFIG"
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
load_menu_items() {
    menu_items=()
    silent_includes=()
    assigned_hotkeys=()

    # --- DYNAMICALLY RESRVE STATIC HOTKEYS (MODIFIED BLOCK) ---
    # Loop through the centralized global_toggles array to reserve keys
    for option_line in "${global_toggles[@]}"; do
        IFS='|' read -r hotkey _ _ <<< "$option_line"
        assigned_hotkeys["${hotkey,,}"]=1
    done

    # Also reserve 'u' for Re-enter URL and '+' for Run
    assigned_hotkeys["u"]=1
    assigned_hotkeys["+"]=1 # Though '+' won't clash with generate_hotkey, better to be explicit.

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

    local state="$1" # "locked" or "active"
    local countdown_value="$2"

    clear
    echo -e "\n${B_WHITE}--- LLM-PACKAGE Menu ---${NC}"

    if [ "$state" == "locked" ]; then
        echo -e "\n Paste URL or press any key to edit.\n"
    else
        echo -e "Edit the menu and prompts dynamically by changing folder names, filenames and contents in ../yt-menu/prompts/\n"
        echo -e "${YELLOW}Target:${NC} $url"
        echo -e "${YELLOW}Current Selections:${NC}"
        # ... (Print active selections loop - this comment remains) ...
        echo ""
    fi

    # --- MENU ITEMS ---
    for i in "${!menu_items[@]}"; do
        IFS='|' read -r hotkey cat item _ _ _ special color <<< "${menu_items[$i]}"

        if [ "$state" == "locked" ]; then
            # DIMMED MODE (MODIFIED)
            # --- START of CHANGE 1 ---
            local status="[ ]"
            # Check if the index is in our 'selected' map to show sticky state
            [[ -v "selected_indices[$i]" ]] && status="[x]"
            # Use the status variable instead of a hardcoded "[ ]"
            printf " ${GRAY}%s %s [%-8s] | %s${NC}\n" "$hotkey." "$status" "$cat" "$item"
            # --- END of CHANGE 1 ---
        else
            # ACTIVE MODE
            local status="[ ]"
            [[ -v "selected_indices[$i]" ]] && status="[${GREEN}x${NC}]"
            # Use %b for status to interpret the color codes
            printf " %s %b ${color}[%-8s]${NC} | %s\n" "$hotkey." "$status" "$cat" "$item"
        fi
    done

    # --- FOOTER ---
    echo ""
    for option_line in "${global_toggles[@]}"; do
        IFS='|' read -r hotkey desc var_name <<< "$option_line"

        # --- REFACTOR START ---
        # 1. Prepare the final description text for BOTH states first.
        local current_desc="$desc"
        if [[ "$hotkey" == "t" ]]; then
            current_desc="${current_desc} (${opt_timer_seconds}s)."
        fi

        # 2. Determine the status ([ ] or [x]) for BOTH states.
        local status="[ ]"
        local var_value="${!var_name}"
        [[ "$var_value" == true ]] && status="[x]"
        # --- REFACTOR END ---

        if [ "$state" == "locked" ]; then
            # LOCKED / DIMMED FORMAT
            # Now it uses the correct 'current_desc' and 'status'
            printf " ${GRAY}%s %s %s${NC}\n" "$hotkey." "$status" "$current_desc"
        else
            # ACTIVE FORMAT
            # Overwrite status with the colored version if active
            [[ "$var_value" == true ]] && status="[${GREEN}x${NC}]"
            # Now it also uses the correct 'current_desc'
            printf " %s %b ${B_WHITE}%s${NC}\n" "$hotkey." "$status" "$current_desc"
        fi
    done
    echo ""
    if [[ "$state" == "active" ]]; then
        if [[ "$opt_timer_enabled" == true && -n "$countdown_value" && "$countdown_value" -gt 0 ]]; then
            printf "${YELLOW} Auto-run in %2ss... |${NC}" "$countdown_value"
        fi

        # Action/Navigation options
        echo -e "${B_BLUE} Enter Hotkey to toggle, or ${B_WHITE}+${B_BLUE} to Run${NC}"
        echo ""
        printf " %s %b\n" "u." "${B_WHITE}Re-enter URL..${NC}"
        echo "" # Add trailing newline for clean prompt placement
    fi
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
    comments_basedir="$BASE_DIR"
    opt_no_sticky="${OPT_NO_STICKY:-$opt_no_sticky}"
    opt_timer_enabled="${OPT_TIMER_ENABLED:-$opt_timer_enabled}"
    opt_timer_seconds="${OPT_TIMER_SECONDS:-$opt_timer_seconds}"
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

# --- 3. INTERFACE LOOP ---

url=""
menu_active=false
run_countdown=-1 # Use -1 to signify timer is not currently running

while true; do
    if [ -z "$url" ]; then
        # === STATE 1: LOCKED / PASTE MODE ===
        display_menu "locked"
        echo -e "\n${B_GREEN}Paste URL: ${NC}"
        tput cuu 1; tput cuf 11
        read -e -r url_input
        if [ -z "$url_input" ]; then continue; fi

        url="$url_input"

#     Disableroony to disallow non url entries in Paste URL, yeah baby
#         if [[ "$url" != http* ]]; then
#             echo "Invalid URL. Must start with http." >&2; sleep 1; url=""; continue
#         fi

        # URL is valid, ACTIVATE TIMER if enabled
        if [ "$opt_timer_enabled" = true ]; then
            run_countdown=$opt_timer_seconds
        fi

    else
        # === STATE 2: ACTIVE / MENU MODE ===
        if [ "$run_countdown" -eq 0 ]; then
            echo -e "\n[yt-menu] Timer finished. Running..."
            # Use a short sleep to let the user see the message
            sleep 0.5
            break # Exit loop to run the program
        fi

        display_menu "active" "$run_countdown"
        printf "${B_WHITE}Choice: ${NC}"

        # Use read with a 1-second timeout if the timer is active
        input_char=""
        if [ "$run_countdown" -gt 0 ]; then
            # Wait for input with a 1-second timeout.
            if read -r -n 1 -t 1 input_char; then
                # Key was pressed: Stop the countdown immediately.
                run_countdown=-1
            else
                # Timeout occurred: Decrement the countdown and redraw.
                ((run_countdown--))
                continue
            fi
        else # Timer is not active, wait for input indefinitely
            read -r -n 1 input_char || break
        fi

        # --- PROCESS INPUTS ---

        # Settings Items
        if [[ "$input_char" == "+" ]]; then break; fi
        # `u` needs echo
        if [[ "$input_char" == "u" ]]; then url=""; run_countdown=-1; continue; fi
        if [[ "$input_char" == "o" || "$input_char" == "O" ]]; then
            if [[ "$omit_comments" == true ]]; then omit_comments=false; else omit_comments=true; fi
            continue
        fi
        if [[ "$input_char" == "d" || "$input_char" == "D" ]]; then
            if [[ "$opt_no_sticky" == true ]]; then opt_no_sticky=false; else opt_no_sticky=true; fi
            # Update config immediately regarding the preference
            update_config_file
            continue
        fi
        if [[ "$input_char" == "x" || "$input_char" == "X" ]]; then
            if [[ "$opt_no_save_this_run" == true ]]; then opt_no_save_this_run=false; else opt_no_save_this_run=true; fi
            continue
        fi
        if [[ "$input_char" == "t" || "$input_char" == "T" ]]; then
            if [[ "$opt_timer_enabled" == true ]]; then
                opt_timer_enabled=false
                run_countdown=-1 # Deactivate timer for this run
                echo -e "\n${YELLOW}Auto-run timer DISABLED.${NC}"; sleep 1
            else
                opt_timer_enabled=true
                echo "" # Newline for prompt
                printf "${YELLOW}Enter countdown in seconds (current: %s): ${NC}" "$opt_timer_seconds"
                read -r new_seconds
                if [[ "$new_seconds" =~ ^[0-9]+$ && "$new_seconds" -gt 0 ]]; then
                    opt_timer_seconds=$new_seconds
                elif [ -n "$new_seconds" ]; then
                    echo "Invalid input. Keeping current value." >&2; sleep 1
                fi
                # Activate timer for this run immediately
                run_countdown=$opt_timer_seconds
            fi
            update_config_file # Save preference
            continue
        fi

        # Normal selections
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
                    ## Below shows previously saved prompt in editor. However, it's completely broken since the input field is trash and it's not possible to delete previous lines.
                    #if [ -n "$custom_prompt_text" ]; then echo -e "${CYAN}Current:${NC} $custom_prompt_text"; fi

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

    fi
done

# --- 4. Finalize State & Assemble ---
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
        if [ "$transcription_was_skipped" = true ]; then
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
# Analyzes subs, prints info about selections, chooses the most desirable
# (exact native match, primary tag match, English fallback, or first available)
# and converts it's identifier into the actual call for that actual subtitle according to YT API

echo "[yt-menu] Phase 2: Subtitle analysis..."
mapfile -t available_sub_langs < <(jq -r '(.subtitles // {}) + (.automatic_captions // {}) | keys[]' "$info_json_file" | sort -u)
original_lang=$(jq -r '.language // "en"' "$info_json_file")
echo "[yt-menu]   -> Video native language detected: $original_lang"
if [ ${#available_sub_langs[@]} -gt 0 ]; then
    echo "[yt-menu]   -> Available subtitles: ${available_sub_langs[*]}"
else
    echo "[yt-menu]   -> No subtitles found in metadata."
fi

best_lang_to_download=""
download_reason="" # Store the reason for selection

if [ ${#available_sub_langs[@]} -gt 0 ]; then
    # 1. Exact match
    for lang in "${available_sub_langs[@]}"; do
        if [[ "$lang" == "$original_lang" ]]; then
            best_lang_to_download="$lang"
            download_reason="Exact match for native language ($original_lang)"
            break
        fi
    done

    # 2. Primary tag match (en from en-US)
    if [ -z "$best_lang_to_download" ] && [[ "$original_lang" == *-* ]]; then
        primary="${original_lang%%-*}"
        for lang in "${available_sub_langs[@]}"; do
            if [[ "$lang" == "$primary" ]]; then
                best_lang_to_download="$lang"
                download_reason="Primary tag match for native language ($primary)"
                break
            fi
        done
    fi
    # 3. Fallback to English
    if [ -z "$best_lang_to_download" ]; then
        for lang in "${available_sub_langs[@]}"; do
            if [[ "$lang" == "en" ]]; then
                best_lang_to_download="$lang"
                download_reason="Fallback to English (en)"
                break
            fi
        done
    fi
    # 4. First available
    if [ -z "$best_lang_to_download" ]; then
        best_lang_to_download="${available_sub_langs[0]}"
        download_reason="Selecting first available language: ${available_sub_langs[0]}"
    fi

    if [ -n "$best_lang_to_download" ]; then
        echo "[yt-menu]   -> Selection logic: $download_reason" # NEW: Print the selection reason
        echo "[yt-menu]   -> Downloading subtitle: $best_lang_to_download"
        "${YTDLP_COMMAND_ARRAY[@]}" --no-playlist --write-subs --write-auto-subs --sub-lang "$best_lang_to_download" --sub-format "srt/ass/best" --skip-download --ignore-errors --ignore-config --paths "$tmp_dir" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url"
    fi
fi

# --- COUNTING COMMENTS ---
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

if [ -z "$structured_transcription_file" ]; then transcription_was_skipped=true; fi

# --- FINAL PACKAGE ---
echo "[yt-menu] Creating final package..."
package_basename=$(basename "${base_filename}.llm-package.json")
temp_package_path="$tmp_dir/$package_basename"

# Generate new metadata fields not present in the info.json
generation_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # ISO 8601 format

# Start building jq arguments. We will pass the info.json as the main input context to jq.
jq_args=(
    --arg filename "$package_basename"
    --arg gen_date "$generation_date"
    --arg comment_count "$comment_count"
    --arg user_url_input "$url"
)

# Start building the jq filter string. This creates the base object with expanded metadata.
# Using `// fallback` provides graceful handling for optional/missing keys from yt-dlp.
jq_filter='
{
  metadata: {
    llm_package_filename: $filename,
    llm_package_generation_date: $gen_date,
    title: .title,
    id: .id,
    webpage_url: .webpage_url,
    user_supplied_url: $user_url_input,
    upload_date: .upload_date,
    duration_string: .duration_string,
    was_live: (.was_live // null),
    location: (.location // null),
    uploader: .uploader,
    channel: .channel,
    channel_url: .channel_url,
    channel_follower_count: (.channel_follower_count // null),
    view_count: (.view_count // null),
    like_count: (.like_count // null),
    dislike_count: (.dislike_count // null),
    total_comments: (.comment_count // null),
    comment_count: $comment_count,
    average_rating: (.average_rating // null),
    rating_count: (.rating_count // null),
    tags: (.tags // []),
    playlist: (.playlist // null),
    playlist_index: (.playlist_index // null),
    playlist_webpage_url: (.playlist_webpage_url // null)
  }
}
'

# Conditionally add other data components to the jq command
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

# Inject Instructions (Append)
if [ -n "$llm_instructions_json" ]; then
    # We reuse the $inst variable defined in the prepend block
    jq_filter="$jq_filter"' + {llm_instructions_reminder: $inst}'
fi

# Execute the final, combined jq command, reading from the info.json file
jq "${jq_args[@]}" "$jq_filter" "$info_json_file" > "$temp_package_path"

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
