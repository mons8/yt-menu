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



# This script prompts the user for a URL and then passes it to yt-dlp with flags for downloading only commends and description.

# Source the master environment file. It defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
# The path is relative to this script's location.
source "$(dirname "$0")/../lib/environment.sh"

# --- Configuration ---
config_file="$WORK_DIR/config/yt-comments.cfg"
comments_basedir=""

if [ -f "$config_file" ] && [ -r "$config_file" ]; then
    read -r comments_basedir < "$config_file"
fi

if [ -z "$comments_basedir" ]; then
    if [ -t 0 ]; then # Check for interactive terminal
        echo "Config file ($config_file) not found or base directory not set."
        while [ -z "$comments_basedir" ]; do
            printf "Enter your desired base download dir for comments: "
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
    echo "Using base directory from yt-comments.cfg: $comments_basedir"
fi
# --- End Configuration ---
# This block runs if the file didn't exist, was unreadable, or was empty.
if [ -z "$comments_basedir" ]; then
    echo "Config file ($config_file) not found or base directory not set."

    # Loop until the user provides a non-empty path.
    while [ -z "$comments_basedir" ]; do
        printf "Enter your desired base download dir for comments: "
        read -r comments_basedir
        if [ -z "$comments_basedir" ]; then
            echo "Path cannot be empty. Please try again."
        fi
    done

    # Save the new path to the config file (creates or overwrites).
    echo "$comments_basedir" > "$config_file"
    echo "Music Base Directory set to: $comments_basedir"
    echo "Saved to $config_file"
# else
#     # The path was successfully read from the config file.
#     echo "Using base directory from yt-comments.cfg: $comments_basedir"
fi
# --- End Configuration ---

# Prompt the user for a URL without adding a newline at the end.
printf "Enter URL: "

# Read the user's input into variable 'url'.
# '-r' flag prevents backslash interpretation, which is important for URLs.
read -r url

# Execute command
echo "Downloading comments to $comments_basedir"
$YTDLP_COMMAND \
    --write-comments \
    --skip-download \
    --ignore-config \
    --write-description \
    --paths "$comments_basedir" \
    --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" \
    "$url"

## yt-dlp --write-comments --write-description --skip-download --ignore-config -P "$music_basedir" "$url"
