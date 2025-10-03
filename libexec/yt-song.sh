#!/bin/bash

# This script downloads individual songs. It manages a
# separate configuration file (yt-song.cfg) for the base directory
# of single song downloads.

# Source the master environment file. It defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
source "$(dirname "$0")/../lib/environment.sh"

# --- Configuration ---
config_file="$WORK_DIR/config/yt-song.cfg"
music_basedir=""

if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r music_basedir < "$config_file"
fi

if [ -z "$music_basedir" ]; then
    if [ -t 0 ]; then # CRITICAL: Guard against non-interactive execution
        echo "Config file ($config_file) not found or base directory not set."
        while [ -z "$music_basedir" ]; do
            printf "Enter your desired base directory for single songs (e.g., /home/user/Music/Singles): "
            read -r music_basedir
            if [ -z "$music_basedir" ]; then
                echo "Path cannot be empty. Please try again."
            fi
        done
        echo "$music_basedir" > "$config_file"
        echo "Music Base Directory set to: $music_basedir"
        echo "Saved to $config_file"
    else
        echo "Error: Base directory not configured in '$config_file'. Cannot prompt in non-interactive mode." >&2
        exit 1
    fi
else
    echo "Using base directory from $config_file: $music_basedir"
fi
# --- End Configuration ---



# --- User Input ---
printf "Target URL: "
read -r target_url

# Validate that a URL was provided.
if [ -z "$target_url" ]; then
    echo "Target URL cannot be empty. Exiting."
    exit 1
fi

printf "Input NEW folder name under %s (or leave blank): " "$music_basedir"
read -r subfolder_name


# --- Prepare and Execute yt-dlp ---

# To avoid repeating the long command, we define the common arguments first.
YT_DLP_ARGS=(
    -f bestaudio
    --extract-audio
    --audio-format mp3
    --audio-quality 0
    --embed-thumbnail
    --ignore-config
    --no-playlist
    --parse-metadata "playlist_index:(?P<meta_track>.*)"
    --parse-metadata ":(?P<meta_date>)"
    --embed-metadata
    --replace-in-metadata "channel" " - Topic$" ""
)

# Determine the final download path based on user input.
if [ -z "$subfolder_name" ]; then
    # Case 1: No subfolder provided. Download directly to the base path.
    download_path="$music_basedir"
    echo "Downloading song(s) to \"$download_path\""
else
    # Case 2: Subfolder provided. Combine base path and subfolder name.
    download_path="$music_basedir/$subfolder_name"
    echo "Downloading song(s) to \"$download_path\""
fi

# Execute the final command. This single command handles both cases.
$YTDLP_COMMAND \
    -paths "$download_path" \
    -o '%(channel)s - %(title)s.%(ext)s' \
    "${YT_DLP_ARGS[@]}" \
    "$target_url"

exit 0
