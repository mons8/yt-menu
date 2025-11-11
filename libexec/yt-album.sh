#!/bin/bash

# Copyright (C) 2025 mons8 <115350611+mons8@users.noreply.github.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.



# This script provides yt-dlp flags to download a playlist as a mp3 album.
# It manages a configuration file to store the base directory for music downloads.


# # --- Diagnostic ---
# if [ -n "$BASH_VERSION" ]; then
#     echo "Running with BASH version: $BASH_VERSION"
# else
#     echo "WARNING: Not running with BASH. Shell is probably $(ps -p $$ -o comm=)"
# fi
# # --- End Diagnostic ---

# Source the master environment file. It defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
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

# --- User Input for Download ---

printf "Playlist URL: "
read -r playlist_url

# Check for empty URL input
if [ -z "$playlist_url" ]; then
    echo "Playlist URL cannot be empty. Exiting."
    exit 1
fi

printf "Set name for new dir under %s (Leave blank for automatic naming): " "$music_basedir"
read -r album_dir_name

# --- Execute yt-dlp ---

# Argument array
YT_DLP_ARGS=(
    -f bestaudio
    --extract-audio
    --audio-format mp3
    --audio-quality 0
    --embed-thumbnail
    --ignore-config
    --parse-metadata "playlist_index:(?P<meta_track>.*)"
    --parse-metadata ":(?P<meta_date>)"
    --parse-metadata "title:%(title)s:^%(artist)s\s*-\s*(?P<title>.+)"
    --replace-in-metadata "channel" " - Topic$" ""
    --replace-in-metadata "title" " \(Official Video\)" ""
    --replace-in-metadata "title" " \(Audio\)" ""
    --replace-in-metadata "title" " \(Video\)" ""
    --embed-metadata
)


# .cfg-provided directory:

if [ -z "$album_dir_name" ]; then
    # Case 1: Automatic naming (album_dir_name is empty)
    echo "Starting download with automatic naming..."
    $YTDLP_COMMAND \
        -P "$music_basedir" \
        -o '%(channel)s - %(playlist)s/%(playlist_index)s. %(title)s.%(ext)s' \
        "${YT_DLP_ARGS[@]}" \
        "$playlist_url"
else
    # User-provided directory name:
    # We use -P for the path prefix, safer than embedding in -o.
    download_path="$music_basedir/$album_dir_name"
    echo "Downloading album to \"$download_path\""
    $YTDLP_COMMAND \
        -P "$download_path" \
        -o '%(playlist_index)s. %(title)s.%(ext)s' \
        "${YT_DLP_ARGS[@]}" \
        "$playlist_url"
fi

exit 0
