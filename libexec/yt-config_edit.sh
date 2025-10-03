#!/bin/sh

# This script opens the yt-dlp config file with nano.

set -e

# Adhere to the XDG Base Directory Specification.
# Use $XDG_CONFIG_HOME if set, otherwise default to $HOME/.config.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp"
config_file="$config_dir/config"

# Ensure the configuration directory exists before attempting to open the file.
mkdir -p "$config_dir"

# Replace the current shell process with nano.
exec nano "$config_file"
