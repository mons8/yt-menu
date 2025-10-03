#!/bin/bash

# This script provides a centralized function to manage settings in the main config file.
# It should be sourced by other scripts, not executed directly.

# Ensure WORK_DIR is set. The sourcing script must have sourced environment.sh first.
if [ -z "$WORK_DIR" ]; then
    echo "FATAL: WORK_DIR not set. Sourcing environment.sh is a prerequisite." >&2
    exit 1
fi

CONFIG_FILE="$WORK_DIR/config/yt-menu.cfg"

# --- Function: get_config ---
# Reads a value from the config file. If not found or empty, prompts the user.
# Exits with an error if prompting is required in a non-interactive session.
#
# Usage:
#   local my_var
#   my_var=$(get_config "KEY_NAME" "Prompt message for the user")
#
get_config() {
    local key="$1"
    local prompt_msg="$2"
    local value=""

    # Create the config file from defaults if it doesn't exist.
    if [ ! -f "$CONFIG_FILE" ]; then
        # This assumes data/config.defaults exists.
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cp "$WORK_DIR/data/config.defaults" "$CONFIG_FILE"
    fi

    # Read the value from the file. The grep/cut is robust.
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${key}=" "$CONFIG_FILE" | cut -d'=' -f2-)
    fi

    # If the value is still empty, we must prompt or fail.
    if [ -z "$value" ]; then
        if [ -t 0 ]; then # Interactive terminal?
            echo "Configuration for '$key' not found or not set."
            while [ -z "$value" ]; do
                printf "%s: " "$prompt_msg"
                read -r value
                if [ -z "$value" ]; then
                    echo "Path cannot be empty. Please try again."
                fi
            done

            # Save the new value back to the config file.
            # This method safely updates the key or appends it if it doesn't exist.
            local temp_file
            temp_file=$(mktemp)
            grep -v "^${key}=" "$CONFIG_FILE" > "$temp_file"
            echo "${key}=${value}" >> "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
            echo "Saved '$key' to $CONFIG_FILE"

        else # Not interactive. This is a fatal error.
            echo "Error: Configuration key '$key' is not set in '$CONFIG_FILE'." >&2
            echo "Cannot prompt in a non-interactive mode. Please configure it manually." >&2
            exit 1
        fi
    fi

    # The final value is echoed to be captured by the calling script.
    echo "$value"
}