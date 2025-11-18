#!/bin/bash

# Provides a function to copy a string to the system clipboard.
# Relies on the YT_CLIPBOARD_CMD environment variable being defined
# (e.g., in environment.sh) to a valid clipboard command.
#
# Examples for YT_CLIPBOARD_CMD:
#   "wl-copy"
#   "xclip -selection clipboard"
#   "pbcopy"
#
# Usage in another script:
#   source "$(dirname "$0")/../lib/clipboard.sh"
#   copy_to_clipboard "some string"

copy_to_clipboard() {
    local data_to_copy="$1"
    # Extract the command name, ignoring arguments (e.g., "xclip" from "xclip -selection clipboard")
    local cmd_name="${YT_CLIPBOARD_CMD%% *}"

    # Silently exit if no command is configured or if the command is not in PATH.
    if [ -z "$YT_CLIPBOARD_CMD" ] || ! command -v "$cmd_name" &>/dev/null; then
        return
    fi

    if printf "%s" "$data_to_copy" | $YT_CLIPBOARD_CMD; then
        # Log to stderr to avoid polluting stdout of the calling script.
        echo "[yt-menu] Path copied to clipboard via '$YT_CLIPBOARD_CMD'." >&2
    else
        echo "[yt-menu] Warning: Failed to copy data to clipboard using '$YT_CLIPBOARD_CMD'." >&2
    fi
}