#!/bin/bash

# --- PRE-FLIGHT CHECKS ---
if ! command -v jq &> /dev/null; then
    echo "[yt-menu] Error: 'jq' command not found." >&2; exit 1; fi

source "$(dirname "$0")/../lib/environment.sh"

# --- CONFIGURATION & URL INPUT ---
config_file="$WORK_DIR/config/yt-comments.cfg"
comments_basedir=""
if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r comments_basedir < "$config_file"
fi
if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then
        echo "[yt-menu] Config file ($config_file) not found or base directory not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for comments: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then
                echo "[yt-menu] Path cannot be empty. Please try again."
            fi
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

printf "Enter URL for download and append \"+\" for prompt menu. Confirm with Enter: "
read -r url
if [ -z "$url" ]; then
    echo "[yt-menu] Error: URL cannot be empty." >&2; exit 1;
fi

# --- INTERACTIVE PROMPT SELECTION MENU ---

# Styling
NC='\e[0m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
B_GREEN='\e[1;32m'
B_YELLOW='\e[1;33m'
B_WHITE='\e[1;37m'
CYAN='\e[0;36m'

# Menu Definition: Category|Menu Text|Prompt Payload
menu_items=(
    "FORMAT|Plain-text|Any analysis of this json object must be structured in pure plain-text only."
    "FORMAT|Markdown spreadsheet|Wherein reasonable and applicable any analysis of this json object must be structured as a Markdown spreadsheet."
    "TONE|Brilliant & Disagreeable|Any analysis of this json object must have the tone and timbre of that of a virtuous and brilliant mind. Does not care for convention and seeks the truth. Low agreeability. Kind-hearted and severe. Assumes audience is very intelligent. Does not casually or needlessly expound. Keeps it tight. Does not omit anything of interest or pertinence. Has an advanced sense of when to answer tersely and when not to hold anything back."
    "TASK|Executive Summary|Provide a dense, high-level summary of the video's core message, intended for a knowledgeable and time-constrained audience. Omit pleasantries and introductory phrases."
    "TASK|Key Takeaways (Bulleted)|Extract the most critical, actionable, or memorable points from the transcript and present them as a concise bulleted list."
    "TASK|Comment Sentiment Analysis|Analyze the sentiment of the comments section. Identify the dominant emotional tones, categorize the top 3-5 recurring themes or arguments, and note any significant shifts in opinion or common points of confusion."
    "TASK|Deconstruct Core Argument|Identify the primary thesis of the video. Sequentially list the main arguments or claims made in support of this thesis. For each argument, note the evidence or reasoning provided in the transcript."
    "TASK|Extract Actionable Items|Scan the transcript and comments for any concrete advice, recommended actions, tools, resources, or unresolved questions. Collate these into a structured list."
    "CUSTOM|Enter Custom Prompt|-"
)

# State variables
selected_formatting_name=""
selected_formatting_prompt=""
selected_tone_name=""
    selected_tone_prompt=""
declare -A selected_tasks
custom_prompt=""

while true; do
    clear
    echo -e "${B_WHITE}--- Configure LLM Instructions ---${NC}"

    # Display current selections
    echo -e "${B_YELLOW}Current Selections:${NC}"
    [ -n "$selected_formatting_name" ] && echo -e "  ${CYAN}Format:${NC} $selected_formatting_name"
    [ -n "$selected_tone_name" ] && echo -e "  ${CYAN}Tone:${NC} $selected_tone_name"
    if [ ${#selected_tasks[@]} -gt 0 ]; then
        echo -e "  ${CYAN}Tasks:${NC}"
        for task_name in "${!selected_tasks[@]}"; do echo "    - $task_name"; done
    fi
    [ -n "$custom_prompt" ] && echo -e "  ${CYAN}Custom Prompt:${NC} [Present]"
    echo ""
    # Display menu options
    i=1
    for item in "${menu_items[@]}"; do
        IFS='|' read -r category name _ <<< "$item"
        
        status="[ ]"
        case "$category" in
            FORMAT) [[ "$name" == "$selected_formatting_name" ]] && status="[${GREEN}x${NC}]";;
            TONE) [[ "$name" == "$selected_tone_name" ]] && status="[${GREEN}x${NC}]";;
            TASK) [[ -v "selected_tasks[$name]" ]] && status="[${GREEN}x${NC}]";;
            CUSTOM) [[ -n "$custom_prompt" ]] && status="[${GREEN}x${NC}]";;
        esac

        # FIX 1: Use printf for formatting, then echo -e to render ANSI codes
        line=$(printf "%2d. %s %-30s" "$i" "$status" "$name")
        echo -e "$line"
        ((i++))
    done
    echo ""
    echo -e "${B_GREEN} d. Done - Proceed with Download${NC}"
    echo ""

    printf "${B_WHITE}Choice: ${NC}"
    read -r -n 1 choice

    if [[ "$choice" == "d" || "$choice" == "D" ]]; then break; fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#menu_items[@]}" ]; then continue; fi

    index=$((choice - 1))
    IFS='|' read -r category name prompt <<< "${menu_items[$index]}"

    case "$category" in
        FORMAT)
            selected_formatting_name="$name"; selected_formatting_prompt="$prompt" ;;
        TONE)
            selected_tone_name="$name"; selected_tone_prompt="$prompt" ;;
        TASK)
            if [[ -v "selected_tasks[$name]" ]]; then unset "selected_tasks[$name]"; else selected_tasks["$name"]="$prompt"; fi ;;
        CUSTOM)
            echo -e "\n\n${B_CYAN}Enter your custom multi-line prompt. End with 'EOF' on a new line.${NC}"
            # FIX 2: Use <<- to allow indented here-document delimiter
            read -r -d '' custom_prompt <<- 'EOF'
			EOF
            ;;
    esac
done

# --- END OF MENU ---

tmp_dir=$(mktemp -d)
cleanup() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "[yt-menu] Script finished successfully. Removing temporary directory." >&2
        rm -rf "$tmp_dir"
    else
        echo "[yt-menu] Script exited with error code $exit_code. Preserving temporary directory for inspection:" >&2
        echo "[yt-menu] -> $tmp_dir" >&2
    fi
}
trap cleanup EXIT

# --- DOWNLOAD ASSETS ---
echo "[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Downloading assets to temporary directory: $tmp_dir"
"${YTDLP_COMMAND_ARRAY[@]}" --write-comments --write-info-json --write-description --write-auto-subs --sub-langs "^en(-[a-zA-Z]+)*$" --sub-format "srt/ass/best" --skip-download --ignore-config --paths "$tmp_dir" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url"
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
video_id="${id_and_date_part%%\]*}"
upload_date="${id_and_date_part##*.}"
channel="${channel_and_title_part%% - *}"
video_title="${channel_and_title_part#* - }"
video_url="https://www.youtube.com/watch?v=${video_id}"
echo "[yt-menu]   -> Channel: $channel"
echo "[yt-menu]   -> Title: $video_title"
echo "[yt-menu]   -> ID: $video_id"
echo "[yt-menu]   -> Date: $upload_date"
echo "[yt-menu] -----------------------------------------------------"

# --- RESTRUCTURE COMMENTS VIA PYTHON ---
echo "[yt-menu] Restructuring comments into a threaded format..."
python_script_path="$WORK_DIR/libexec/json-restructurer.py"
stderr_file=$(mktemp)
threaded_comments_file=$("$VENV_PYTHON" "$python_script_path" "$info_json_file" 2> "$stderr_file")
if [ $? -ne 0 ]; then
    echo "[yt-menu] Error: Python script exited." >&2
    echo "[yt-menu] Python stderr: $(<"$stderr_file")" >&2
fi; rm "$stderr_file"
if [ -n "$threaded_comments_file" ] && [ -f "$threaded_comments_file" ]; then
    echo "[yt-menu] SUCCESS: Threaded comments file created at '$threaded_comments_file'"; rm "$info_json_file"
else
    echo "[yt-menu] FAILURE: Threaded comments file was NOT created."; threaded_comments_file=""
fi
echo "[yt-menu] -----------------------------------------------------"

# --- SELECT BEST SUBTITLE ---
echo "[yt-menu] Selecting best subtitle..."
shopt -s nullglob; all_sub_files=("$base_filename".*.{srt,ass}); shopt -u nullglob
best_sub_file=
