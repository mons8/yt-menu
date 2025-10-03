#!/bin/sh

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
