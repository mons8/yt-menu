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



# This script opens the yt-dlp config file with nano.

set -e


# --- LOAD ENV FILE ---
source "$(dirname "$0")/../lib/environment.sh"

# Ensure the configuration directory exists before attempting to open the file.
mkdir -p "$config_dir"

# Replace the current shell process with nano.
exec nano "$config_file"
