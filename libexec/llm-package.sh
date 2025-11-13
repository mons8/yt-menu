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

# --- URL INPUT MODIFICATION ---
prompt_menu_requested=false
printf "Enter URL for download. Append \"+\" for prompt menu. Confirm with Enter: "
read -r url_input
if [[ "$url_input" == *+ ]]; then
    prompt_menu_requested=true
    url="${url_input%+}"
else
    url="$url_input"
fi

if [ -z "$url" ]; then
    echo "[yt-menu] Error: URL cannot be empty." >&2; exit 1;
fi


# --- INTERACTIVE PROMPT SELECTION MENU ---

llm_instructions_json=""
if [ "$prompt_menu_requested" = true ]; then
    # Styling
    NC='\e[0m'
    GREEN='\e[0;32m'
    YELLOW='\e[0;33m'
    B_GREEN='\e[1;32m'
    B_YELLOW='\e[1;33m'
    WHITE='\e[0;37m'
    B_WHITE='\e[1;37m'
    CYAN='\e[0;36m'

    # Menu Definition: Category|Menu Text|Prompt Payload
    menu_items=(
        "FORMAT|Plain Text|Any analysis of this json object must be formatted in pure plain-text only."
        "FORMAT|Markdown Spreadsheet|Wherein reasonable and applicable any analysis of this json object must be structured as a Markdown spreadsheet."
        "TONE|Brilliant & Disagreeable|Any analysis of these json objects must maintain the tone and timbre of that of a virtuous and brilliant mind. A mind which does not care for convention, a mind which virtously seeks the truth. Low agreeability. Kind-hearted and severe. Assumes audience is very intelligent. Does not casually or needlessly expound. Keeps it tight. Does not omit anything of interest or pertinence. Has an advanced sense of when to answer tersely and when not to hold anything back."
        "TASK|Answer the question!|Provide a pithy answer to any clickbait posed in the title or deduced from description, transcription or comments below."
        "TASK|Brief summary and recap|Firstly, from the transcription we must pithily detail the core communications and take-aways in a way which is easily digestable to a gifted, knowledgeable and time-constrained audience. Then elaborate further by providing an accurate, impartial and dense, brief and none too granular, \"play-by-play\" summary of the same material. We mustn't reference timecodes excessively. It's supposed to relay the relevant info in a sequential manner so as to not miss anything important. If there's noting of importance to relay, well, then say so and leave it at that.  It's of paramount importance to report simply the content which is being relayed in the transcription material. That means that we must not embroider, moralize, edit, sanction nor opinionize."
        "TASK|Devil's advocate|Accurately and tersely construct a fair representation of the primary thesis and all supporting points from the transcription and then proceed to savagely disassemble any and all vulnerable points with surgical precision. It's is sensible to focus mainly on the weakest points, the tender bits, so to speak, but it's always important to not over-extend the attack and maintain a balanced center."
        "TASK|Actionable ways to intelligently explore this subject further|Extract and collate concrete and actionable intelligence and _build upon it_. In the first instance, include everthing noteworthy from the material at hand with a special consideration to anything actionable. In the second phase (which need not be explicitly structured as such), apply your own discrete and brilliant interpretation and tidbits and clues regarding where to go for further investigate. Structure for maximum utility and immediate application."
        "TASK|Comments Briefing|Process the comments to provide a valuable briefing. We are interested in the gist of what is said, as well as what the most erudite and elegant comments and discussions bring to the table in this conversation. Use your own judgement regarding how to structure and angle the report. You may detail relevant trends of agreement or disagreement or common points of confusion. It may be beneficial to include a some (or many!) _high-value_ comments verbatim in the report. Do not omit anything of pertinence. Finally but crucially, it is very important to include an estimation of what commenters feel about the subject matter. The preferred way is a bar graph showing approximate percentages of users expressing a set of pertinent attitudes."
        "CUSTOM|Custom Prompt|-"
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
        echo -e "${B_WHITE}--- Prompt Configuration ---${NC}"

        echo -e "${B_YELLOW}Current Selections:${NC}"
        [ -n "$selected_formatting_name" ] && echo -e "  ${CYAN}Format:${NC} $selected_formatting_name"
        [ -n "$selected_tone_name" ] && echo -e "  ${CYAN}Tone:${NC} $selected_tone_name"
        if [ ${#selected_tasks[@]} -gt 0 ]; then
            echo -e "  ${CYAN}Tasks:${NC}"
            for task_name in "${!selected_tasks[@]}"; do echo "    - $task_name"; done
        fi
        [ -n "$custom_prompt" ] && echo -e "  ${CYAN}Custom Prompt:${NC} [Present]"
        echo ""
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

            category_color=""
            category_tag=""
            case "$category" in
                FORMAT) category_color="$WHITE";    category_tag="[FORMAT]";;
                TONE)   category_color="$B_YELLOW"; category_tag="[  TONE]";;
                TASK)   category_color="$GREEN";    category_tag="[  TASK]";;
                CUSTOM) category_color="$B_WHITE";  category_tag="[CUSTOM]";;
            esac

            line=$(printf "%2d. %s %-18s %s" "$i" "$status" "${category_color}${category_tag}${NC}" "$name")
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
                echo -e "\n\n${B_WHITE}Enter your custom multi-line prompt. End with 'EOF' on a new line:${NC}"
                line=""
                buffer=""
                while IFS= read -r line; do
                    if [[ "$line" == "EOF" ]]; then
                        break
                    fi
                    buffer+="${line}"$'\n'
                done
                custom_prompt="${buffer%$'\n'}"
                ;;
        esac
    done

    # --- ASSEMBLE PROMPT PAYLOAD ---
    echo ""
    echo "[yt-menu] -----------------------------------------------------"
    echo "[yt-menu] Assembling LLM instructions with new format..."

    # 1. Format the single-selection prompts (Format and Tone)
    formatted_format_prompt=""
    if [ -n "$selected_formatting_name" ]; then
        formatted_format_prompt=" * ${selected_formatting_name}: ${selected_formatting_prompt}"
    fi

    formatted_tone_prompt=""
    if [ -n "$selected_tone_name" ]; then
        formatted_tone_prompt=" * ${selected_tone_name}: ${selected_tone_prompt}"
    fi

    # 2. Format the multi-selection prompts (Tasks) and build a JSON array
    tasks_json_array="[]"
    if [ ${#selected_tasks[@]} -gt 0 ]; then
        formatted_task_prompts_for_jq=()
        for name in "${!selected_tasks[@]}"; do
            prompt="${selected_tasks[$name]}"
            formatted_string=" * ${name}: ${prompt}"
            # Add the formatted string to a temporary bash array
            formatted_task_prompts_for_jq+=("$formatted_string")
        done
        # Use jq to safely convert the bash array into a JSON array string
        tasks_json_array=$(jq -n --compact-output '[$ARGS.positional]' --args "${formatted_task_prompts_for_jq[@]}")
    fi

    # 3. Use jq to construct the final instructions object from the newly formatted shell variables.
    #    The custom prompt is used as-is.
    llm_instructions_json=$(jq -n \
        --arg format "$formatted_format_prompt" \
        --arg tone "$formatted_tone_prompt" \
        --argjson tasks "$tasks_json_array" \
        --arg custom "$custom_prompt" \
        '{
            "text-formatting": $format,
            "tone-and-timbre": $tone,
            "essential-tasks-instructions-considerations": $tasks,
            "high-priority-instruction": $custom
        } | with_entries(select(.value | IN("", [], null) | not))')

    if [ -z "$llm_instructions_json" ] || [ "$llm_instructions_json" == "{}" ]; then
        echo "[yt-menu] No LLM instructions were selected. Skipping injection."
        llm_instructions_json=""
    else
        echo "[yt-menu] LLM instructions assembled successfully."
    fi
fi

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
shopt -s nullglob
all_sub_files=("$base_filename".*.{srt,ass})
shopt -u nullglob
best_sub_file=""
if [ ${#all_sub_files[@]} -gt 0 ]; then
    priorities=("en-en" "en-orig" "en-US" "en")
    for priority in "${priorities[@]}"; do
        for file in "${all_sub_files[@]}"; do
            if [[ "$file" == *."$priority".* ]]; then
                best_sub_file="$file"; break 2; fi
        done
    done
    if [ -z "$best_sub_file" ]; then
        best_sub_file="${all_sub_files[0]}"; fi
fi
if [ -n "$best_sub_file" ]; then
    echo "[yt-menu] Best subtitle found: $(basename "$best_sub_file")"
else
    echo "[yt-menu] No preferred subtitle file found."
fi
echo "[yt-menu] -----------------------------------------------------"
# --- PROCESS TRANSCRIPTION (FORMAT-AWARE) ---
structured_transcription_file=""
if [ -n "$best_sub_file" ]; then
    echo "[yt-menu] Processing transcription into structured format..."

    case "$best_sub_file" in
        *.srt)
            echo "[yt-menu]   -> Detected SRT format. Using srt-processor.py."
            python_script_path="$WORK_DIR/libexec/srt-processor.py"
            structured_transcription_file=$("$VENV_PYTHON" "$python_script_path" "$best_sub_file")
            ;;
        *.ass)
            echo "[yt-menu]   -> Detected ASS format. Using ass-processor.py."
            python_script_path="$WORK_DIR/libexec/ass-processor.py"
            structured_transcription_file=$("$VENV_PYTHON" "$python_script_path" "$best_sub_file")
            ;;
        *)
            echo "[yt-menu]   -> Warning: Unsupported subtitle format for structuring: $(basename "$best_sub_file")" >&2
            ;;
    esac

    if [ ! -s "$structured_transcription_file" ]; then
        echo "[yt-menu]   -> Warning: Python processor failed to create a valid structured file." >&2
        structured_transcription_file=""
    else
        echo "[yt-menu]   -> Successfully created structured transcription file."
    fi
fi
echo "[yt-menu] -----------------------------------------------------"

# --- AGGREGATE FINAL LLM PACKAGE ---
echo "[yt-menu] Aggregating all data into a final LLM JSON package..."
package_basename=$(basename "${base_filename}.llm-package.json")
temp_package_path="$tmp_dir/$package_basename"

jq_command_args=()
jq_filter_parts=()

# 1. Conditionally add START instructions.
if [ -n "$llm_instructions_json" ]; then
    jq_command_args+=(--argjson instructions "$llm_instructions_json")
    jq_filter_parts+=('"llm_instructions_start": $instructions')
fi

# 2. Add the static metadata key.
jq_command_args+=(--arg title "$video_title" --arg channel "$channel" --arg video_id "$video_id" --arg upload_date "$upload_date" --arg video_url "$video_url")
jq_filter_parts+=('"metadata": {"title": $title, "channel": $channel, "video_id": $video_id, "upload_date": $upload_date, "url": $video_url}')

# 3. Conditionally add the other data keys.
if [ -f "$description_file" ]; then
    jq_command_args+=(--rawfile description_data "$description_file")
    jq_filter_parts+=('"description": $description_data')
fi

if [ -n "$structured_transcription_file" ]; then
    jq_command_args+=(--slurpfile transcription_data "$structured_transcription_file")
    jq_command_args+=(--arg transcription_format_desc "The transcription is an array where each element is [startTime, endTime, text].")
    jq_filter_parts+=('"transcription": {"format_description": $transcription_format_desc, "data": $transcription_data[0]}')
fi

if [ -n "$threaded_comments_file" ]; then
    jq_command_args+=(--slurpfile comments_data "$threaded_comments_file")
    jq_filter_parts+=('"comments": $comments_data[0]')
fi

# FINAL JQ EXECUTION
if [ ${#jq_filter_parts[@]} -gt 0 ]; then
    base_jq_filter="{$(IFS=,; echo "${jq_filter_parts[*]}")}"
    final_jq_filter="$base_jq_filter"

    if [ -n "$llm_instructions_json" ]; then
        final_jq_filter="$base_jq_filter | {llm_instructions_start, metadata} + . | . + {llm_instructions_end: \$instructions}"
    fi

    jq -n "${jq_command_args[@]}" "$final_jq_filter" > "$temp_package_path"

    if [ $? -eq 0 ] && [ -s "$temp_package_path" ]; then
        final_destination_path="$comments_basedir/$package_basename"
        echo "[yt-menu] Successfully created package, moving to: $final_destination_path"
        mv "$temp_package_path" "$final_destination_path"
    else
        echo "[yt-menu] Error: Failed to create JSON package. JQ exited with an error." >&2; exit 1;
    fi
else
    echo "[yt-menu] No data sources found to aggregate. Skipping package creation."
fi
echo "[yt-menu] -----------------------------------------------------"
echo "[yt-menu] All workflows complete."
