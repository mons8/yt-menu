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
        echo "[yt-menu] $comments_basedir" > "$config_file"
        echo "[yt-menu] Comments Base Directory set to: $comments_basedir"
        echo "[yt-menu] Saved to $config_file"
    else
        echo "[yt-menu] Error: Base directory not configured in '$config_file'. Cannot prompt." >&2
        exit 1
    fi
else
    echo "[yt-menu] Using base directory from yt-comments.cfg: $comments_basedir"
fi

printf "Enter URL for download: "
read -r url
tmp_dir=$(mktemp -d)
#trap 'rm -rf "$tmp_dir"' EXIT
# Replaced above unconditional tmp cleanup with a function which leaves the tmp folder alone if error code exit
cleanup() {
    # Capture the exit code of the last command before the trap was triggered (into a variable: $?).
    local exit_code=$?

    # If the script exited successfully (code 0), clean up.
    if [ $exit_code -eq 0 ]; then
        # Use >&2 for logging messages to not pollute stdout
        echo "[yt-menu] Script finished successfully. Removing temporary directory." >&2
        rm -rf "$tmp_dir"
    else
        # On error print location of the temp files for debugging.
        echo "[yt-menu] Script exited with error code $exit_code. Preserving temporary directory for inspection:" >&2
        echo "[yt-menu] -> $tmp_dir" >&2
    fi
}

# trap registers the cleanup function to be executed whenever the script exits, for any reason  (success, error, or explicit exit call).
trap cleanup EXIT

# --- END MODIFICATION ---

# --- DOWNLOAD ASSETS ---
echo "[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Downloading assets to temporary directory: $tmp_dir"
"${YTDLP_COMMAND_ARRAY[@]}" \
    --write-comments --write-info-json --write-description \
    --write-auto-subs --sub-langs "^en(-[a-zA-Z]+)*$" --sub-format "srt/ass/best" \
    --skip-download --ignore-config --paths "$tmp_dir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" \
    "$url"

if [ $? -ne 0 ]; then
    echo "[yt-menu] Error: yt-dlp exited with a non-zero status. Aborting." >&2; exit 1; fi
echo "[yt-menu] -----------------------------------------------------"

mapfile -t all_created_files < <(find "$tmp_dir" -type f)
if [ ${#all_created_files[@]} -eq 0 ]; then
    echo "[yt-menu] Error: yt-dlp ran successfully but created no files." >&2; exit 1; fi

info_json_file=""
for file in "${all_created_files[@]}"; do
    if [[ "$file" == *.info.json ]]; then
        info_json_file="$file"; break; fi
done
if [ -z "$info_json_file" ]; then
    echo "[yt-menu] Error: Could not find the .info.json file among the downloaded assets." >&2; exit 1; fi

base_filename="${info_json_file%.info.json}"
description_file="$base_filename.description"

# --- NEW: PARSE FILENAME FOR METADATA ---
echo "[yt-menu] Parsing filename for metadata..."
fname_no_path=$(basename "$base_filename")
# Extract parts using robust parameter expansion
id_and_date_part="${fname_no_path##* \[}"      # "SojXUePKCU4].20251105"
channel_and_title_part="${fname_no_path%% \[*}" # "Hyperborean Knowledge  - Loosh Harvesting Witches (Soul Trap)"

video_id="${id_and_date_part%%\]*}"           # "SojXUePKCU4"
upload_date="${id_and_date_part##*.}"         # "20251105"
channel="${channel_and_title_part%% - *}"    # "Hyperborean Knowledge"
video_title="${channel_and_title_part#* - }" # "Loosh Harvesting Witches (Soul Trap)"
video_url="https://www.youtube.com/watch?v=${video_id}"

echo "[yt-menu]   -> Channel: $channel"
echo "[yt-menu]   -> Title: $video_title"
echo "[yt-menu]   -> ID: $video_id"
echo "[yt-menu]   -> Date: $upload_date"
echo "[yt-menu] -----------------------------------------------------"

# --- RESTRUCTURE COMMENTS VIA PYTHON ---
echo "[yt-menu] Restructuring comments into a threaded format..."
# CHANGED: Path to the new script
python_script_path="$WORK_DIR/libexec/json-restructurer.py"
python_command=("$VENV_PYTHON" "$python_script_path" "$info_json_file")

stderr_file=$(mktemp)
threaded_comments_file=$("${python_command[@]}" 2> "$stderr_file")
python_exit_code=$?
python_stderr=$(<"$stderr_file")
rm "$stderr_file"

if [ $python_exit_code -ne 0 ]; then
    echo "[yt-menu] Error: Python script exited with code $python_exit_code." >&2
    echo "[yt-menu] Python stderr:" >&2
    echo "[yt-menu] $python_stderr" >&2
fi

if [ -n "$threaded_comments_file" ] && [ -f "$threaded_comments_file" ]; then
    echo "[yt-menu] SUCCESS: Threaded comments file created at '$threaded_comments_file'"
    rm "$info_json_file" # Original is no longer needed
else
    echo "[yt-menu] FAILURE: Threaded comments file was NOT created. Check Python script output."
    threaded_comments_file=""
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

    # Use a case statement to select the correct processor based on file extension.
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

# 1. Add ALL top-level keys to a single array for robust joining.
#    Start with the static metadata key.
jq_command_args+=(--arg title "$video_title" --arg channel "$channel" --arg video_id "$video_id" --arg upload_date "$upload_date" --arg video_url "$video_url")
jq_filter_parts+=('"metadata": {"title": $title, "channel": $channel, "video_id": $video_id, "upload_date": $upload_date, "url": $video_url}')

# 2. Conditionally add the other data keys to the SAME array.
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
# Only proceed if we have something to build. The metadata part will always be there.
if [ ${#jq_filter_parts[@]} -gt 0 ]; then
    # 3. Join all parts with a comma. This is now guaranteed to be syntactically correct.
    final_jq_filter="{$(IFS=,; echo "${jq_filter_parts[*]}")}"

    # Debugging: Print the exact command that will be run.
    # echo "[yt-menu] Executing jq with filter: $final_jq_filter" >&2

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
