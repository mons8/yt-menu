#!/bin/bash

# This script sets up the environment for all yt-menu scripts.

# Define path to work directory, location of all scripts
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )" # Points to project root

# Define the absolute path to your venv's Python interpreter.
VENV_PYTHON="$WORK_DIR/.venv/bin/python3"

# Define the full, non-argument part of the command by replicating the exec line.
YTDLP_COMMAND="$VENV_PYTHON -Werror -Xdev $WORK_DIR/vendor/yt-dlp/yt_dlp/__main__.py"

# MODERN: Robust array for new and updated scripts.
# Use with "${YTDLP_COMMAND_ARRAY[@]}"
YTDLP_COMMAND_ARRAY=(
    "$VENV_PYTHON"
    "-Werror"
    "-Xdev"
    "$WORK_DIR/vendor/yt-dlp/yt_dlp/__main__.py"
)

# Use with "${YTDLP_COMMAND_ARRAY_NONERROR[@]}"
YTDLP_COMMAND_ARRAY_NONERROR=(
    "$VENV_PYTHON"
    "$WORK_DIR/vendor/yt-dlp/yt_dlp/__main__.py"
)
