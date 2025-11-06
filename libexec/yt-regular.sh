#!/bin/sh

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



# This script prompts the user for a URL and then passes it to yt-dlp.

# Prompt the user for a URL without adding a newline at the end.
printf "Enter URL: "

# Read the user's input into a variable named 'url'.
# The '-r' flag prevents backslash interpretation, which is important for URLs.
read -r url

# Execute yt-dlp, passing the user's input as a single argument.
# It is CRITICAL to double-quote the variable "$url" to handle URLs
# that contain special characters like '&', '?', or spaces.
yt-dlp "$url"
