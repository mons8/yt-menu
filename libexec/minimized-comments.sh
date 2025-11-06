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

# --- Download and Capture Filename ---
# We no longer need the timestamping method. We will capture the exact filename from yt-dlp.
echo "Downloading comments and description to $comments_basedir"

# The `info_json_file=$(...)` syntax captures the standard output of the command into the variable.
# yt-dlp progress bars are printed to stderr, so they won't be captured.
info_json_file=$("${YTDLP_COMMAND_ARRAY[@]}" \
    --write-comments \
    --write-info-json \
    --write-description \
    --skip-download \
    --ignore-config \
    --paths "$comments_basedir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" \
    --print "after_move:%(info_dict.filepath)s" \ # <-- SLIGHTLY MORE ROBUST PRINT??
    "$url")

# --- Post-Download Processing ---
echo "-----------------------------------------------------"

# Check if yt-dlp returned a filename. If not, it likely failed.
if [ -z "$info_json_file" ]; then
    echo "Error: yt-dlp did not return a filename. Download may have failed." >&2
    exit 1
fi

# Check if the file actually exists, just in case.
if [ ! -f "$info_json_file" ]; then
    echo "Error: The file reported by yt-dlp does not exist: $info_json_file" >&2
    exit 1
fi

python_script_path="$WORK_DIR/libexec/json-restructurer.py"

echo "File created: $info_json_file"
echo "Executing JSON minimization script..."

# Execute the python script with the single correct argument (the input file).
"$VENV_PYTHON" "$python_script_path" "$info_json_file"

if [ $? -eq 0 ]; then
    echo "Script execution successful."
else
    echo "Warning: JSON minimization script failed with an error." >&2
fi

# --- Cleanup ---
echo "-----------------------------------------------------"
echo "Cleaning up original info.json file..."
echo "Deleting: $info_json_file"
rm "$info_json_file"

echo "Cleanup complete."
