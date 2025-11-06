#!/bin/bash

# This script prompts the user for a URL and then passes it to yt-dlp.

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
            printf "Enter your desired base download dir for transcriptions and descriptions: "
            read -r comments_basedir
            if [ -z "$comments_basedir" ]; then
                echo "Path cannot be empty. Please try again."
            fi
        done
        echo "$comments_basedir" > "$config_file"
        # CORRECTED PROMPT:
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

# Prompt the user for a URL without adding a newline at the end.
printf "Enter URL for download of transcription: "

# Read the user's input into variable 'url'.
# '-r' flag prevents backslash interpretation, which is important for URLs.
read -r url

# Execute command
echo "Downloading comments to $comments_basedir"
$YTDLP_COMMAND \
    --write-auto-subs --sub-langs "^en(-[a-zA-Z]+)*$" \
    --sub-format "srt/ass/best" \
    --skip-download \
    --ignore-config \
    --write-description \
    --paths "$comments_basedir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" \
    "$url"

## yt-dlp --write-comments --write-description --skip-download --ignore-config -P "$music_basedir" "$url"
