#!/bin/bash

# --- PRE-FLIGHT CHECKS ---
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found." >&2; exit 1; fi

source "$(dirname "$0")/../lib/environment.sh"
# ... (Configuration block is unchanged) ...
config_file="$WORK_DIR/config/yt-comments.cfg"
comments_basedir=""
if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r comments_basedir < "$config_file"
fi
if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then
        echo "Config file ($config_file) not found or base directory not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for comments: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then
                echo "Path cannot be empty. Please try again."
            fi
        done
        echo "$comments_basedir" > "$config_file"
        echo "Comments Base Directory set to: $comments_basedir"
        echo "Saved to $config_file"
    else
        echo "Error: Base directory not configured in '$config_file'. Cannot prompt." >&2
        exit 1
    fi
else
    echo "Using base directory from yt-comments.cfg: $comments_basedir"
fi

printf "Enter URL for download: "
read -r url
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

echo "-----------------------------------------------------"
echo "Downloading assets to temporary directory: $tmp_dir"
# ... (yt-dlp call is unchanged) ...
"${YTDLP_COMMAND_ARRAY[@]}" \
    --write-comments --write-info-json --write-description \
    --write-auto-subs --sub-langs "^en(-[a-zA-Z]+)*$" --sub-format "srt/ass/best" \
    --skip-download --ignore-config --paths "$tmp_dir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" \
    "$url"

if [ $? -ne 0 ]; then
    echo "Error: yt-dlp exited with a non-zero status. Aborting." >&2
    exit 1
fi
echo "-----------------------------------------------------"
mapfile -t all_created_files < <(find "$tmp_dir" -type f)
if [ ${#all_created_files[@]} -eq 0 ]; then
    echo "Error: yt-dlp ran successfully but created no files." >&2; exit 1; fi
info_json_file=""
for file in "${all_created_files[@]}"; do
    if [[ "$file" == *.info.json ]]; then
        info_json_file="$file"; break; fi
done
if [ -z "$info_json_file" ]; then
    echo "Error: Could not find the .info.json file among the downloaded assets." >&2; exit 1; fi

base_filename="${info_json_file%.info.json}"
description_file="$base_filename.description"

#
# --- DEBUG BLOCK 1: PYTHON SCRIPT (CORRECTED CAPTURE LOGIC) ---
#
echo "--- BEGIN DEBUG: Comment Minimization ---"
python_script_path="$WORK_DIR/libexec/json-restructurer.py"
python_command=("$VENV_PYTHON" "$python_script_path" "$info_json_file")
printf "Executing command: %q %q %q\n" "${python_command[@]}"

# This is the robust way to capture stdout, stderr, and exit code separately.
# 1. Create a temporary file to hold stderr.
stderr_file=$(mktemp)
# 2. Run the command. Assign stdout to the variable directly (no subshell for this assignment).
#    Redirect stderr to the temporary file.
minimized_comments_file=$("${python_command[@]}" 2> "$stderr_file")
python_exit_code=$?
# 3. Read the contents of the stderr file into the other variable.
python_stderr=$(<"$stderr_file")
# 4. Clean up the temporary file.
rm "$stderr_file"

echo "Python script stdout (assigned to minimized_comments_file):"
echo ">>>$minimized_comments_file<<<"
echo "Python script stderr:"
echo ">>>$python_stderr<<<"
echo "Python script exit code: $python_exit_code"

# Post-execution checks
if [ -n "$minimized_comments_file" ] && [ -f "$minimized_comments_file" ]; then
    echo "SUCCESS: Minimized comments file was created at '$minimized_comments_file'"
    rm "$info_json_file"
else
    echo "FAILURE: Minimized comments file was NOT created or path is invalid."
    minimized_comments_file=""
fi
echo "--- END DEBUG: Comment Minimization ---"
echo "-----------------------------------------------------"

# ... (The rest of the script is unchanged and should now work) ...
echo "Selecting best subtitle..."
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
    echo "Best subtitle found: $(basename "$best_sub_file")"
else
    echo "No preferred subtitle file found."
fi
echo "-----------------------------------------------------"
echo "Aggregating all data into a final JSON package..."
package_basename=$(basename "${base_filename}.package.json")
temp_package_path="$tmp_dir/$package_basename"
jq_command_args=()
jq_filter_parts=()
if [ -f "$minimized_comments_file" ]; then
    jq_command_args+=(--slurpfile comments_data "$minimized_comments_file")
    jq_filter_parts+=('"comments": $comments_data[0]')
fi
if [ -f "$description_file" ]; then
    jq_command_args+=(--rawfile description_data "$description_file")
    jq_filter_parts+=('"description": $description_data')
fi
if [ -n "$best_sub_file" ] && [ -f "$best_sub_file" ]; then
    jq_command_args+=(--rawfile transcription_data "$best_sub_file")
    jq_filter_parts+=('"transcription": $transcription_data')
fi
if [ ${#jq_filter_parts[@]} -gt 0 ]; then
    final_jq_filter="{$(IFS=,; echo "${jq_filter_parts[*]}")}"
    jq -n "${jq_command_args[@]}" "$final_jq_filter" > "$temp_package_path"
    if [ $? -eq 0 ] && [ -f "$temp_package_path" ]; then
        final_destination_path="$comments_basedir/$package_basename"
        echo "Successfully created package, moving to: $final_destination_path"
        mv "$temp_package_path" "$final_destination_path"
    else
        echo "Error: Failed to create JSON package." >&2
    fi
else
    echo "No data sources found to aggregate. Skipping package creation."
fi
echo "-----------------------------------------------------"
echo "All workflows complete. Temporary files will be cleaned up automatically."
