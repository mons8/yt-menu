#!/bin/bash

# This script prompts the user for a URL and then passes it to yt-dlp to download comments.

# Source the master environment file. It defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
# The path is relative to this script's location.
source "$(dirname "$0")/../lib/environment.sh"

# --- Configuration ---
config_file="$WORK_DIR/config/subs.cfg"
comments_basedir=""

if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r comments_basedir < "$config_file"
fi

if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then # Check for interactive terminal
        echo "Config file ($config_file) not found or base directory not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for comments and descriptions: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then
                echo "Path cannot be empty. Please try again."
            fi
        done
        echo "$comments_basedir" > "$config_file"
        echo "Comments Base Directory set to: $comments_basedir"
        echo "Saved to $config_file"
    else
        # Fail cleanly when not interactive
        echo "Error: Base directory not configured in '$config_file'. Cannot prompt in non-interactive mode." >&2
        exit 1
    fi
else
    echo "Using base directory from configuration file: $comments_basedir"
fi
# --- End Configuration ---

printf "Enter URL for download of comments/description: "
read -r url

timestamp_file="/tmp/subs_timestamp_$$"
touch "$timestamp_file"
trap 'rm -f "$timestamp_file"' EXIT

echo "Downloading comments and description to $comments_basedir"
$YTDLP_COMMAND \
    --write-comments \
    --write-info-json \
    --write-description \
    --skip-download \
    --ignore-config \
    --paths "$comments_basedir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s" \
    "$url"

# --- Post-Download Processing ---
echo "-----------------------------------------------------"
echo "Searching for newly downloaded info.json file..."
mapfile -t new_json_files < <(find "$comments_basedir" -newer "$timestamp_file" -type f -name "*.info.json")

if [ ${#new_json_files[@]} -eq 0 ]; then
    echo "No new info.json file was found. Nothing to process."
    exit 0
fi

if [ ${#new_json_files[@]} -gt 1 ]; then
    echo "Warning: Found multiple new info.json files. Processing only the first one."
fi

info_json_file="${new_json_files[0]}"
python_script_path="$WORK_DIR/libexec/json-minimizer.py"

echo "Found file for processing: $info_json_file"
echo "Executing JSON minimization script..."

# Execute the python script with the single correct argument (the input file).
"$VENV_PYTHON" "$python_script_path" "$info_json_file"

# Check the exit code of the last command.
if [ $? -eq 0 ]; then
    echo "Script execution successful."
else
    echo "Warning: JSON minimization script failed with an error." >&2
fi

# --- Cleanup ---
echo "-----------------------------------------------------"
echo "Cleaning up original info.json file..."
if [ -f "$info_json_file" ]; then
    echo "Deleting: $info_json_file"
    rm "$info_json_file"
else
    echo "Original file '$info_json_file' not found for deletion."
fi

echo "Cleanup complete."