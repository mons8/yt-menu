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
# This prompts for creation of new subfolder but it adds another prompt, a whole extra step. I don't like it
# printf "Input NEW folder name under %s (or leave blank): " "$music_basedir"
# read -r subfolder_name


# --- Prepare and Execute yt-dlp ---

download_path="$music_basedir"
if [ -n "$subfolder_name" ]; then
    download_path="$music_basedir/$subfolder_name"
fi
echo "Downloading song(s) to \"$download_path\""

# Consolidate all arguments into a single array for robust execution.
# Note the correction to --replace-in-metadata syntax.
yt_dlp_final_args=(
    -P "$download_path"
    -o '%(channel)s - %(title)s.%(ext)s'
    -f 'bestaudio'
    --extract-audio
    --audio-format mp3
    --audio-quality 0
    --embed-thumbnail
    --ignore-config
    --no-playlist
    --parse-metadata 'playlist_index:(?P<meta_track>.*)'
    --parse-metadata ':(?P<meta_date>)'
    --embed-metadata
    --replace-in-metadata 'channel' ' - Topic$' ''
    "$target_url"
)

"${YTDLP_COMMAND_ARRAY[@]}" "${yt_dlp_final_args[@]}"

exit 0
