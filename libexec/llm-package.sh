#!/bin/bash

# --- CONSTANTS & CONFIGURATION ---
set -o pipefail
NC='\e[0m'
GREEN='\e[0;32m'
B_WHITE='\e[1;37m'
YELLOW='\e[0;33m'
B_YELLOW='\e[1;33m'
CYAN='\e[0;36m'
B_BLUE='\e[1;34m'
B_CYAN='\e[1;36m'

# The directory containing the prompt files, relative to the script
PROMPT_DIR="$(dirname "$0")/../prompts"

# Global flag to track if transcription was created, for the final report.
TRANSCRIPTION_WAS_SKIPPED=false

# --- LIBRARY & PRE-FLIGHT ---
if ! command -v jq &> /dev/null; then echo "[yt-menu] Error: 'jq' command not found." >&2; exit 1; fi
if ! command -v realpath &> /dev/null; then echo "[yt-menu] Error: 'realpath' command not found. Please install it (e.g., coreutils)." >&2; exit 1; fi
if [ ! -d "$PROMPT_DIR" ]; then echo "[yt-menu] Error: Prompt directory not found at '$PROMPT_DIR'." >&2; exit 1; fi

source "$(dirname "$0")/../lib/environment.sh"

# --- FUNCTIONS ---

# Loads menu items from the file system into a global array.
load_menu_items() {
    menu_items=()
    while IFS= read -r file; do
        local category_part=$(basename "$(dirname "$file")")
        local name_part=$(basename "$file")
        local category="${category_part#*-}"
        local name_raw="${name_part#*-}"
        local name="${name_raw//_/ }"
        local prompt=$(<"$file")
        menu_items+=("$category|$name|$prompt")
    done < <(find "$PROMPT_DIR" -type f ! -name ".*" | sort)
}

# Displays the interactive prompt selection menu.
display_menu() {
    clear
    echo -e "\n${B_WHITE}--- Prompt Configuration ---${NC}\n"
    echo -e "${YELLOW}Current Selections:${NC}"
    local has_selections=false
    for i in $(printf '%s\n' "${!selected_indices[@]}" | sort -n); do
        IFS='|' read -r category name _ <<< "${menu_items[$i]}"
        echo -e "  ${CYAN}${category}:${NC} $name"
        has_selections=true
    done
    [ -n "$custom_prompt" ] && { echo -e "  ${CYAN}CUSTOM:${NC} [Present]"; has_selections=true; }
    [[ "$has_selections" == false ]] && echo "  None"
    echo ""
    for i in "${!menu_items[@]}"; do
        IFS='|' read -r category name _ <<< "${menu_items[$i]}"
        local status="[ ]"
        # CORRECTED: Check for selection index OR if the item is CUSTOM and its prompt is set.
        if [[ -v "selected_indices[$i]" ]]; then
            status="[${GREEN}x${NC}]"
        elif [[ "$category" == "CUSTOM" && -n "$custom_prompt" ]]; then
            status="[${GREEN}x${NC}]"
        fi
        local category_color=""
        case "$category" in
            FORMAT)   category_color="$YELLOW";; TONE)     category_color="$B_BLUE";;
            TASK)     category_color="$B_CYAN";; COMMENTS) category_color="$B_YELLOW";;
            CUSTOM)   category_color="$B_WHITE";;
        esac
        printf "%2d. %b ${category_color}[%-8s]${NC} | %s\n" "$((i+1))" "$status" "$category" "$name"
    done
    echo -e "\n${B_BLUE} Enter ${B_WHITE}+${B_BLUE} When Done${NC}\n"
}

# Assembles the final LLM instructions JSON from selections.
assemble_prompt_payload() {
    local formatted_format_prompt=""
    local formatted_tone_prompt=""
    declare -a task_prompts_for_jq=()
    for i in $(printf '%s\n' "${!selected_indices[@]}" | sort -n); do
        if [[ -v "selected_indices[$i]" ]]; then
            IFS='|' read -r category name prompt <<< "${menu_items[$i]}"
            local formatted_string=" * ${name}: ${prompt}"
            case "$category" in
                FORMAT) formatted_format_prompt="$formatted_string" ;;
                TONE)   formatted_tone_prompt="$formatted_string" ;;
                *)      task_prompts_for_jq+=("$formatted_string") ;;
            esac
        fi
    done
    local tasks_json_array
    tasks_json_array=$(jq -n --compact-output '[$ARGS.positional]' --args "${task_prompts_for_jq[@]}")
    jq -n \
        --arg format "$formatted_format_prompt" --arg tone "$formatted_tone_prompt" \
        --argjson tasks "$tasks_json_array" --arg custom "$custom_prompt" \
        '{
            "text-formatting": $format, "tone-and-timbre": $tone,
            "essential-tasks-instructions-considerations": $tasks,
            "high-priority-instruction": $custom
        } | with_entries(select(.value | IN("", [], null) | not))'
}


# --- SCRIPT BODY ---

# --- Configuration & URL Input ---
config_file="$WORK_DIR/config/yt-comments.cfg"
comments_basedir=""
if [ -f "$config_file" ] && [ -r "$config_file" ]; then read -r comments_basedir < "$config_file"; fi
if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then
        echo "[yt-menu] Config file ($config_file) not found or base directory not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for comments: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then echo "[yt-menu] Path cannot be empty. Please try again."; fi
        done
        echo "$comments_basedir" > "$config_file"
        echo "[yt-menu] Comments Base Directory set to: $comments_basedir"
        echo "[yt-menu] Saved to $config_file"
    else
        echo "[yt-menu] Error: Base directory not configured in '$config_file'. Cannot prompt." >&2
        exit 1
    fi
else
    echo "[yt-menu] Using base directory from yt-comments.cfg: $comments_basedir"
fi

# --- URL Input Modification ---
prompt_menu_requested=false
printf "Enter URL for download. Append \"+\" for prompt menu. Confirm with Enter: "
read -r url_input
if [[ "$url_input" == *+ ]]; then prompt_menu_requested=true; url="${url_input%+}"; else url="$url_input"; fi
if [ -z "$url" ]; then echo "[yt-menu] Error: URL cannot be empty." >&2; exit 1; fi

# --- INTERACTIVE PROMPT SELECTION MENU ---
llm_instructions_json=""
if [ "$prompt_menu_requested" = true ]; then
    load_menu_items
    declare -A selected_indices
    custom_prompt=""
    while true; do
        display_menu
        printf "${B_WHITE}Choice: ${NC}"
        read -r -n 1 choice
        if [[ "$choice" == "+" ]]; then echo; break; fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#menu_items[@]}" ]; then continue; fi
        index=$((choice - 1))
        IFS='|' read -r category name _ <<< "${menu_items[$index]}"
        if [[ "$category" == "CUSTOM" ]]; then
            echo
            echo -e "\n\n${B_WHITE}Enter your custom multi-line prompt. End with 'EOF' on a new line:${NC}"
            line=""; buffer=""
            while IFS= read -r line; do [[ "$line" == "EOF" ]] && break; buffer+="${line}"$'\n'; done
            custom_prompt="${buffer%$'\n'}"
            continue 
        fi
        if [[ -v "selected_indices[$index]" ]]; then
            unset "selected_indices[$index]"
        else
            if [[ "$category" == "FORMAT" || "$category" == "TONE" ]]; then
                for i in "${!menu_items[@]}"; do
                    if [[ "$i" -ne "$index" ]]; then
                        local other_category; other_category=$(echo "${menu_items[$i]}" | cut -d'|' -f1)
                        if [[ "$other_category" == "$category" ]]; then unset "selected_indices[$i]"; fi
                    fi
                done
            fi
            selected_indices[$index]=1
        fi
    done
    echo -e "\n[yt-menu] -----------------------------------------------------"
    echo "[yt-menu] Inserting prompt content in llm-package payload..."
    llm_instructions_json=$(assemble_prompt_payload)
    if [ -z "$llm_instructions_json" ] || [ "$llm_instructions_json" == "{}" ]; then
        echo "[yt-menu] No LLM instructions were selected. Skipping injection."
        llm_instructions_json=""
    else
        echo "[yt-menu] LLM instructions assembled successfully."
    fi
fi

# --- END OF MENU ---

tmp_dir=$(mktemp -d)
# --- CLEANUP LOGIC ---
cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ -n "$trap_error_suppress" ]; then return; fi
    trap_error_suppress=1

    if [ $exit_code -eq 0 ]; then
        echo "[yt-menu] -----------------------------------------------------"
        # ADDED: Display a warning if the transcription was skipped.
        if [ "$TRANSCRIPTION_WAS_SKIPPED" = true ]; then
            echo -e "[yt-menu] ${B_YELLOW}Warning: No subtitles were found. The final package lacks a transcription.${NC}"
        fi
        echo "[yt-menu] All workflows complete."
#        echo "[yt-menu] Temporary directory is at: $tmp_dir"
#        printf "[yt-menu] Press Enter to delete temporary files and exit..."
#        read -r
        echo -n "[yt-menu] Deleting temp dir at $tmp_dir..."
        sleep 1
        rm -rf "$tmp_dir"
        echo " Done."
    else
        echo "[yt-menu] Script exited with error code $exit_code. Preserving temporary directory for inspection:" >&2
        echo "[yt-menu] -> $tmp_dir" >&2
    fi
}
trap cleanup EXIT

# --- DOWNLOAD ASSETS ---
echo "[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Downloading assets to temporary directory: $tmp_dir"
"${YTDLP_COMMAND_ARRAY[@]}" --write-comments --write-info-json --write-description --write-subs --write-auto-subs --sub-format "srt/ass/best" --skip-download --ignore-config --paths "$tmp_dir" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url"
if [ $? -ne 0 ]; then echo "[yt-menu] Error: yt-dlp exited with a non-zero status. Aborting." >&2; exit 1; fi
echo "[yt-menu] -----------------------------------------------------"

mapfile -t all_created_files < <(find "$tmp_dir" -type f)
if [ ${#all_created_files[@]} -eq 0 ]; then echo "[yt-menu] Error: yt-dlp ran successfully but created no files." >&2; exit 1; fi
info_json_file=""
for file in "${all_created_files[@]}"; do if [[ "$file" == *.info.json ]]; then info_json_file="$file"; break; fi; done
if [ -z "$info_json_file" ]; then echo "[yt-menu] Error: Could not find the .info.json file." >&2; exit 1; fi
base_filename="${info_json_file%.info.json}"
description_file="$base_filename.description"

# --- PARSE FILENAME FOR METADATA ---
echo "[yt-menu] Parsing filename for metadata..."
fname_no_path=$(basename "$base_filename")
id_and_date_part="${fname_no_path##* \[}"
channel_and_title_part="${fname_no_path%% \[*}"
video_id="${id_and_date_part%%\]*}"; upload_date="${id_and_date_part##*.}"
channel="${channel_and_title_part%% - *}"; video_title="${channel_and_title_part#* - }"
video_url="https://www.youtube.com/watch?v=${video_id}"
echo "[yt-menu]   -> Channel: $channel"; echo "[yt-menu]   -> Title: $video_title"
echo "[yt-menu]   -> ID: $video_id"; echo "[yt-menu]   -> Date: $upload_date"
echo "[yt-menu] -----------------------------------------------------"

# --- RESTRUCTURE COMMENTS VIA PYTHON ---
echo "[yt-menu] Restructuring comments into a threaded format..."
python_script_path="$WORK_DIR/libexec/json-restructurer.py"
stderr_file=$(mktemp)
threaded_comments_file=$("$VENV_PYTHON" "$python_script_path" "$info_json_file" 2> "$stderr_file")
if [ $? -ne 0 ]; then echo "[yt-menu] Error: Python script exited." >&2; echo "[yt-menu] Python stderr: $(<"$stderr_file")" >&2; fi
rm "$stderr_file"
if [ -n "$threaded_comments_file" ] && [ -f "$threaded_comments_file" ]; then
    echo "[yt-menu] SUCCESS: Threaded comments file created at '$threaded_comments_file'"
else
    echo "[yt-menu] FAILURE: Threaded comments file was NOT created."; threaded_comments_file=""
fi
echo "[yt-menu] -----------------------------------------------------"

# --- SELECT BEST SUBTITLE ---
echo "[yt-menu] Selecting best subtitle based on metadata..."
original_lang=$(jq -r '.language // "en"' "$info_json_file")
echo "[yt-menu]   -> Video's declared original language: $original_lang"
shopt -s nullglob
# FIX: Drastically simplify 'find' to be robust. It now finds any .srt/.ass
# file in the unique temp directory, avoiding issues with special characters.
mapfile -t all_sub_files < <(find "$tmp_dir" -type f \( -name "*.srt" -o -name "*.ass" \) | sort)
shopt -u nullglob
best_sub_file=""

find_sub_by_lang() {
    local lang_code=$1; shift; local file_list=("$@")
    for file in "${file_list[@]}"; do
        if [[ "$file" =~ \.${lang_code}([-\.][a-zA-Z_-]+)?\.(srt|ass)$ ]]; then echo "$file"; return; fi
    done
}

# Priority 1: Try the full, specific language code (e.g., 'en-US').
best_sub_file=$(find_sub_by_lang "$original_lang" "${all_sub_files[@]}")
if [ -n "$best_sub_file" ]; then
    echo "[yt-menu]   -> Priority 1: Found subtitle matching original language ('$original_lang')."
fi

# Priority 2: If not found, try the primary language sub-tag (e.g., 'en' from 'en-US').
if [ -z "$best_sub_file" ] && [[ "$original_lang" == *-* ]]; then
    primary_lang="${original_lang%%-*}"
    best_sub_file=$(find_sub_by_lang "$primary_lang" "${all_sub_files[@]}")
    if [ -n "$best_sub_file" ]; then
        echo "[yt-menu]   -> Priority 2: Found subtitle matching primary language ('$primary_lang')."
    fi
fi

# Priority 3: If still not found and the original language wasn't English, try English as a fallback.
if [ -z "$best_sub_file" ] && [ "${original_lang%%-*}" != "en" ]; then
    best_sub_file=$(find_sub_by_lang "en" "${all_sub_files[@]}")
    if [ -n "$best_sub_file" ]; then echo "[yt-menu]   -> Priority 3: Found English subtitle as fallback."; fi
fi

# Priority 4: As a last resort, grab the first available subtitle file.
if [ -z "$best_sub_file" ] && [ ${#all_sub_files[@]} -gt 0 ]; then
    best_sub_file="${all_sub_files[0]}"
    echo "[yt-menu]   -> Priority 4: No ideal subtitle found. Using first available as fallback."
fi

if [ -n "$best_sub_file" ]; then echo "[yt-menu] Best subtitle selected: $(basename "$best_sub_file")"
else echo "[yt-menu] No subtitle files of any language were found or downloaded."; fi
echo "[yt-menu] -----------------------------------------------------"
# --- PROCESS TRANSCRIPTION (FORMAT-AWARE) ---
structured_transcription_file=""
if [ -n "$best_sub_file" ]; then
    echo "[yt-menu] Processing transcription into structured format..."
    case "$best_sub_file" in
        *.srt) python_script_path="$WORK_DIR/libexec/srt-processor.py"; structured_transcription_file=$("$VENV_PYTHON" "$python_script_path" "$best_sub_file");;
        *.ass) python_script_path="$WORK_DIR/libexec/ass-processor.py"; structured_transcription_file=$("$VENV_PYTHON" "$python_script_path" "$best_sub_file");;
        *) echo "[yt-menu]   -> Warning: Unsupported subtitle format for structuring: $(basename "$best_sub_file")" >&2;;
    esac
    if [ ! -s "$structured_transcription_file" ]; then
        echo "[yt-menu]   -> Warning: Python processor failed to create a valid structured file." >&2; structured_transcription_file=""
    else echo "[yt-menu]   -> Successfully created structured transcription file."; fi
fi
# ADDED: Set the global flag if no transcription was ultimately produced.
if [ -z "$structured_transcription_file" ]; then
    TRANSCRIPTION_WAS_SKIPPED=true
fi
echo "[yt-menu] -----------------------------------------------------"

# --- AGGREGATE FINAL LLM PACKAGE ---
echo "[yt-menu] Aggregating all data into a final LLM JSON package..."
package_basename=$(basename "${base_filename}.llm-package.json")
temp_package_path="$tmp_dir/$package_basename"
jq_command_args=(); jq_filter_parts=()
if [ -n "$llm_instructions_json" ]; then jq_command_args+=(--argjson instructions "$llm_instructions_json"); jq_filter_parts+=('"llm_instructions_start": $instructions'); fi
jq_command_args+=(--arg title "$video_title" --arg channel "$channel" --arg video_id "$video_id" --arg upload_date "$upload_date" --arg video_url "$video_url")
jq_filter_parts+=('"metadata": {"title": $title, "channel": $channel, "video_id": $video_id, "upload_date": $upload_date, "url": $video_url}')
if [ -f "$description_file" ]; then jq_command_args+=(--rawfile description_data "$description_file"); jq_filter_parts+=('"description": $description_data'); fi
if [ -n "$structured_transcription_file" ]; then jq_command_args+=(--slurpfile transcription_data "$structured_transcription_file"); jq_command_args+=(--arg transcription_format_desc "The transcription is an array where each element is [startTime, endTime, text]."); jq_filter_parts+=('"transcription": {"format_description": $transcription_format_desc, "data": $transcription_data[0]}'); fi
if [ -n "$threaded_comments_file" ]; then jq_command_args+=(--slurpfile comments_data "$threaded_comments_file"); jq_filter_parts+=('"comments": $comments_data[0]'); fi

if [ ${#jq_filter_parts[@]} -eq 0 ]; then echo "[yt-menu] No data sources found to aggregate. Skipping package creation."; else
    base_jq_filter="{$(IFS=,; echo "${jq_filter_parts[*]}")}"; final_jq_filter=""
    if [ -n "$llm_instructions_json" ]; then
        conversation_name_string="llm-package analysis of ${video_title}"
        jq_command_args+=(--arg conversation_name "$conversation_name_string")
        jq_filter_template='({ "name-syntax-for-llm-analysis-chatbot-conversation": $conversation_name } + $instructions) as $modified_instructions | %s | { llm_instructions_start: $modified_instructions, metadata } + . | . + { llm_instructions_end: $modified_instructions }'
        printf -v final_jq_filter "$jq_filter_template" "$base_jq_filter"
    else final_jq_filter="$base_jq_filter"; fi
    jq -n "${jq_command_args[@]}" "$final_jq_filter" > "$temp_package_path"
    if [ $? -eq 0 ] && [ -s "$temp_package_path" ]; then
        final_destination_path="$comments_basedir/$package_basename"
        echo "[yt-menu] Successfully created package, moving to: $final_destination_path"
        mv "$temp_package_path" "$final_destination_path"
        absolute_path=$(realpath "$final_destination_path")
        if command -v wl-copy &> /dev/null; then echo "file://${absolute_path}" | wl-copy --type text/uri-list; echo "[yt-menu] Copied file reference to clipboard via 'wl-copy'.";
        elif command -v xclip &> /dev/null; then echo "file://${absolute_path}" | xclip -selection clipboard -t text/uri-list; echo "[yt-menu] Copied file reference to clipboard via 'xclip'.";
        elif command -v pbcopy &> /dev/null; then cat "$final_destination_path" | pbcopy; echo "[yt-menu] Copied file CONTENTS to clipboard via 'pbcopy' (macOS fallback).";
        elif command -v clip.exe &> /dev/null; then cat "$final_destination_path" | clip.exe; echo "[yt-menu] Copied file CONTENTS to clipboard via 'clip.exe' (WSL fallback).";
        else echo "[yt-menu] No clipboard utility found. Skipping copy."; fi
    else echo "[yt-menu] Error: Failed to create JSON package. JQ exited with an error." >&2; exit 1; fi
fi
# Implicitly passes control to the 'trap cleanup EXIT' function.
