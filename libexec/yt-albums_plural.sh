#!/bin/bash

# This script crawls a channel/user page for playlists, generates a list of
# them using a helper script, and then downloads them (as mp3 albums) using yt-dlp's
# batch file feature (-a).

# --- Prerequisite ---
# This script depends on a python script, releases-retriever.py.
# It depends on python libraries requests and playwright.
# It is expected to take a '--url' argument and print the path to a
# temporary text file containing the list of playlist URLs which then generates a text file of URL's which is passed to yt-dlp.
# --------------------

# Source the master environment file. It defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
# The path is relative to this script's location.
source "$(dirname "$0")/../lib/environment.sh"

# --- Configuration ---
config_file="$WORK_DIR/config/yt-album.cfg"
music_basedir=""

if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r music_basedir < "$config_file"
fi

if [ -z "$music_basedir" ]; then
    # Check if we are running in an interactive terminal.
    if [ -t 0 ]; then
        echo "Config file ($config_file) not found or base directory not set."
        while [ -z "$music_basedir" ]; do
            printf "Enter your desired base directory (e.g., /home/user/Music): "
            read -r music_basedir
            if [ -z "$music_basedir" ]; then
                echo "Path cannot be empty. Please try again."
            fi
        done
        echo "$music_basedir" > "$config_file"
        echo "Music Base Directory set to: $music_basedir"
        echo "Saved to $config_file"
    else
        # Not interactive. This is a fatal error.
        echo "Error: Base directory not configured in '$config_file'. Cannot prompt in non-interactive mode." >&2
        exit 1
    fi
else
    echo "Using Music Base Directory from yt-album.cfg: $music_basedir"
fi
# --- End Configuration ---


# --- User Input ---
printf "Supply URL to crawl for playlists: "
read -r crawl_url

printf "Name of artist: "
read -r artist_name


# --- Retrieve Playlist URLs ---
echo "Running script to retrieve playlists..."

# Ensure tmp-directory exists on which releases-retriever.py depends
mkdir -p "$WORK_DIR/tmp"

# Execute releases-retriever.py and capture its standard output as a variable.
generated_txt_file_path=$("$VENV_PYTHON" "$WORK_DIR/libexec/releases-retriever.py" --url "$crawl_url" --output-dir "$WORK_DIR/tmp")

# Check if the helper script actually returned anything.
if [ -z "$generated_txt_file_path" ]; then
    echo "Error: Playlist retriever script did not return a file path. Exiting."
    exit 1
fi

echo "Playlist file generated at: $generated_txt_file_path"


# --- Execute yt-dlp ---
# - Using -P for the base path for cleanliness.
# - Using single quotes for the output template to protect '%' and '()'.
#   Since we need to include a variable, we must use double quotes instead.
#   This is safe here as the template contains no other shell metacharacters.
# - The batch file path from releases-retriever.py is passed to '-a'.
# - All variables are double-quoted to handle spaces and special characters.
$YTDLP_COMMAND \
    -f bestaudio \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    --embed-thumbnail \
    --ignore-config \
    --parse-metadata "playlist_index:(?P<meta_track>.*)" \
    --parse-metadata ":(?P<meta_date>)" \
    --embed-metadata \
    --replace-in-metadata "channel" " - Topic$" "" \
    --replace-in-metadata "title" " (Official Video)" "" \
    -P "$music_basedir" \
    -o "$artist_name - %(playlist)s/%(playlist_index)s. %(title)s.%(ext)s" \
    -a "$generated_txt_file_path"

exit 0
