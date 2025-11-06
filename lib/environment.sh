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
