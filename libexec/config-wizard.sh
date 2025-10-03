#!/bin/bash
# ==============================================================================
# yt-dlp Configuration Wizard
#
# A script to interactively generate a yt-dlp configuration file.
# Adheres to a strict, modular design. Assumes user intelligence.
# ==============================================================================

# --- Ensure the script is run from an interactive terminal.
if ! [ -t 0 ]; then
    echo "This script must be run interactively from a terminal." >&2
    exit 1
fi

# --- GLOBAL CONFIGURATION ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp"
CONFIG_FILE="$CONFIG_DIR/config"

# --- STYLING ---
NC='\e[0m'; RED='\e[0;31m'; GREEN='\e[0;32m'; YELLOW='\e[0;33m'
B_BLUE='\e[1;34m'; B_WHITE='\e[1;37m'; U_WHITE='\e[4;37m'

# ==============================================================================
# --- STATE MANAGEMENT ---
# Global variables holding the configuration state.
# Prefixed with STATE_ to denote their scope and purpose.
# ==============================================================================
initialize_state() {
    STATE_DL_PATH=""
    STATE_USE_CASE="video"
    STATE_RESOLUTION_SORTER='res:1080,fps' # Default to 1080p
    STATE_AUDIO_FORMAT="best"
    STATE_SUB_WANT="0"
    STATE_SUB_LANGS="en"
    STATE_SUB_EMBED="1"
    STATE_SUB_AUTO="1"
    STATE_OUTPUT_TEMPLATE='%(uploader)s - %(title)s [%(id)s].%(ext)s'
    STATE_EMBED_METADATA="1"
    STATE_EMBED_THUMBNAIL="1"
    STATE_WRITE_COMMENTS="0"
    STATE_SPONSORBLOCK_OP="--sponsorblock-mark all"
    STATE_SAVE_PLAYLIST_ORDER="1"
    STATE_IGNORE_ERRORS="1"
}

# ==============================================================================
# --- CORE LOGIC FUNCTIONS ---
# ==============================================================================

# --- Phase 0: Configuration Parsing ---
load_existing_config() {
    [[ ! -f "$CONFIG_FILE" ]] && { echo -e "${YELLOW}No existing config file found at ${CONFIG_FILE}${NC}"; sleep 2; return 1; }

    initialize_state # Start with defaults, then override

    # Best-effort parser for common options. This is not exhaustive.
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignore comments and empty lines
        [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]] && continue

        # Simple flag parsing
        read -r flag arg <<< "$line"
        arg="${arg#\"}"; arg="${arg%\"}" # Strip outer quotes
        arg="${arg#\'}"; arg="${arg%\'}"

        case "$flag" in
            -P|--paths)               STATE_DL_PATH="$arg" ;;
            -o|--output)              STATE_OUTPUT_TEMPLATE="$arg" ;;
            -S|--format-sort)         STATE_RESOLUTION_SORTER="$arg"; STATE_USE_CASE="video" ;;
            -x|--extract-audio)       STATE_USE_CASE="audio" ;;
            --audio-format)           STATE_AUDIO_FORMAT="$arg" ;;
            --embed-subs)             STATE_SUB_EMBED="1"; STATE_SUB_WANT="1" ;;
            --write-subs)             STATE_SUB_EMBED="0"; STATE_SUB_WANT="1" ;;
            --write-auto-subs)        STATE_SUB_AUTO="1"; STATE_SUB_WANT="1" ;;
            --sub-langs)              STATE_SUB_LANGS="$arg"; STATE_SUB_WANT="1" ;;
            --embed-metadata)         STATE_EMBED_METADATA="1" ;;
            --no-embed-metadata)      STATE_EMBED_METADATA="0" ;;
            --embed-thumbnail)        STATE_EMBED_THUMBNAIL="1" ;;
            --no-embed-thumbnail)     STATE_EMBED_THUMBNAIL="0" ;;
            --write-comments)         STATE_WRITE_COMMENTS="1" ;;
            --sponsorblock-mark)      STATE_SPONSORBLOCK_OP="--sponsorblock-mark $arg" ;;
            --sponsorblock-remove)    STATE_SPONSORBLOCK_OP="--sponsorblock-remove $arg" ;;
            --no-sponsorblock)        STATE_SPONSORBLOCK_OP="--no-sponsorblock" ;;
            --playlist-reverse)       STATE_SAVE_PLAYLIST_ORDER="0" ;;
            -i|--ignore-errors)       STATE_IGNORE_ERRORS="1" ;;
            --no-ignore-errors)       STATE_IGNORE_ERRORS="0" ;;
        esac
    done < "$CONFIG_FILE"
    echo -e "${GREEN}Existing configuration loaded.${NC}"
    sleep 1
}

# --- Phase 1: Initial Questionnaire ---
run_initial_questionnaire() {
    clear
    echo -e "${B_BLUE}--- Phase 1: Initial Setup ---${NC}"
    echo "A few key questions to establish a baseline."

    prompt_for_download_path
    prompt_for_use_case

    # Conditional prompts based on use case
    if [[ "$STATE_USE_CASE" == "video" ]]; then
        prompt_for_resolution
        prompt_for_subtitles
    else
        prompt_for_audio_format
    fi
}

# --- Phase 2: Review & Edit Loop ---
run_review_and_edit_loop() {
    while true; do
        display_current_config
        printf "${B_WHITE}Choice: ${NC}"
        read -r -n 1 choice
        echo

        case "$choice" in
            1) edit_path ;;
            2) edit_output_template ;;
            3) edit_primary_use_case ;;
            4) edit_subtitles ;;
            5) edit_metadata_toggles ;;
            6) edit_sponsorblock ;;
            7) edit_playlist_and_error ;;
            s) save_config_file; break ;;
            q) echo "Quit without saving."; exit 0 ;;
            *) printf "${RED}Invalid option: '%s'${NC}\n" "$choice"; sleep 1 ;;
        esac
    done
}

# --- Phase 3: Finalization ---
save_config_file() {
    clear
    echo -e "${B_BLUE}--- Phase 3: Saving Configuration ---${NC}"

    local config_content
    config_content=$(generate_config_string)

    echo "The following configuration will be saved to:"
    echo -e "${U_WHITE}${CONFIG_FILE}${NC}"
    echo "------------------------------------------------"
    echo -e "${config_content}"
    echo "------------------------------------------------"

    printf "${YELLOW}Proceed with saving? (y/N): ${NC}"
    read -r -n 1 confirm
    echo

    if [[ "$confirm" =~ ^[yY]$ ]]; then
        echo "Creating directory..."
        mkdir -p "$CONFIG_DIR"
        echo "Writing config file..."
        echo -e "$config_content" > "$CONFIG_FILE"
        echo -e "${GREEN}Configuration saved successfully.${NC}"
    else
        echo -e "${RED}Save cancelled.${NC}"
    fi
    sleep 2
}


# ==============================================================================
# --- PROMPT & EDITOR FUNCTIONS ---
# Modular functions for specific settings.
# ==============================================================================

bool_to_human() {
    [[ "$1" == 1 ]] && echo -e "${GREEN}On${NC}" || echo -e "${RED}Off${NC}"
}

prompt_for_download_path() {
    local path
    while true; do
        printf "\n${B_WHITE}1. Enter the absolute path for your downloads:${NC}\n> "
        read -r path
        path="${path/#\~/$HOME}" # Expand tilde

        if [[ -z "$path" ]]; then
            echo -e "${RED}Path cannot be empty.${NC}"
            continue
        fi

        if [ -d "$path" ]; then
            if [ -w "$path" ]; then
                STATE_DL_PATH="$path"
                break
            else
                echo -e "${RED}Directory exists but is not writable.${NC}"
            fi
        else
            printf "${YELLOW}Directory does not exist. Create it? (y/N): ${NC}"
            read -r -n 1 confirm
            echo
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                if mkdir -p "$path"; then
                    echo -e "${GREEN}Directory created.${NC}"
                    STATE_DL_PATH="$path"
                    break
                else
                    echo -e "${RED}Failed to create directory.${NC}"
                fi
            fi
        fi
    done
}

prompt_for_use_case() {
    printf "\n${B_WHITE}2. What is your primary use case?${NC}\n"
    echo "   1. Video (Downloads video files)"
    echo "   2. Audio (Extracts audio only)"
    printf "> "
    read -r -n 1 choice
    echo
    case "$choice" in
        1) STATE_USE_CASE="video" ;;
        2) STATE_USE_CASE="audio" ;;
        *) echo "${YELLOW}Invalid choice. Defaulting to Video.${NC}"; STATE_USE_CASE="video" ;;
    esac
}

prompt_for_resolution() {
    printf "\n${B_WHITE}3. Preferred video resolution?${NC}\n"
    echo "   1. Best available (4K, 8K, etc.)"
    echo "   2. 1080p"
    echo "   3. 720p"
    echo "   4. 480p"
    printf "> "
    read -r -n 1 choice
    echo
    case "$choice" in
        1) STATE_RESOLUTION_SORTER='res,fps' ;;
        2) STATE_RESOLUTION_SORTER='res:1080,fps' ;;
        3) STATE_RESOLUTION_SORTER='res:720,fps' ;;
        4) STATE_RESOLUTION_SORTER='res:480,fps' ;;
        *) echo "${YELLOW}Invalid choice. Defaulting to 1080p.${NC}"; STATE_RESOLUTION_SORTER='res:1080,fps' ;;
    esac
}

prompt_for_audio_format() {
    printf "\n${B_WHITE}3. Preferred audio format?${NC}\n"
    echo "   1. Best (Opus/M4A, highest quality)"
    echo "   2. MP3 (Most compatible)"
    echo "   3. FLAC (Lossless)"
    echo "   4. WAV (Uncompressed)"
    printf "> "
    read -r -n 1 choice
    echo
    case "$choice" in
        1) STATE_AUDIO_FORMAT="best" ;;
        2) STATE_AUDIO_FORMAT="mp3" ;;
        3) STATE_AUDIO_FORMAT="flac" ;;
        4) STATE_AUDIO_FORMAT="wav" ;;
        *) echo "${YELLOW}Invalid choice. Defaulting to best.${NC}"; STATE_AUDIO_FORMAT="best" ;;
    esac
}

prompt_for_subtitles() {
    printf "\n${B_WHITE}4. Download subtitles if available? (y/N): ${NC}"
    read -r -n 1 choice
    echo
    if [[ "$choice" =~ ^[yY]$ ]]; then
        STATE_SUB_WANT="1"
        select_subtitle_languages
    else
        STATE_SUB_WANT="0"
    fi
}

select_subtitle_languages() {
    printf "${B_WHITE}Enter comma-separated language codes (e.g., en,es,ja):${NC}\n"
    printf "[Current: ${STATE_SUB_LANGS}]\n> "
    read -r langs
    [[ -n "$langs" ]] && STATE_SUB_LANGS="$langs"
}

display_current_config() {
    clear
    echo -e "${B_BLUE}--- Review & Edit Configuration ---${NC}"
    echo "Select a number to change its setting. 's' to save, 'q' to quit."
    echo

    # --- Formatting
    local category_format="${B_WHITE}%s${NC}\n"
    local setting_format="  ${B_WHITE}%-2d.${NC} %-25s: %s\n"

    # --- Output & Filename
    printf "$category_format" "Output & Filename"
    printf "$setting_format" 1 "Download Path" "${STATE_DL_PATH:-<Not Set>}"
    printf "$setting_format" 2 "Filename Template" "'${STATE_OUTPUT_TEMPLATE}'"
    echo

    # --- Format Selection
    printf "$category_format" "Format Selection"
    if [[ "$STATE_USE_CASE" == "video" ]]; then
        printf "$setting_format" 3 "Primary Use Case" "Video (Quality: ${STATE_RESOLUTION_SORTER})"
    else
        printf "$setting_format" 3 "Primary Use Case" "Audio (Format: ${STATE_AUDIO_FORMAT})"
    fi
    printf "$setting_format" 4 "Subtitles" "$(bool_to_human "$STATE_SUB_WANT") (Langs: ${STATE_SUB_LANGS}, Embed: $(bool_to_human "$STATE_SUB_EMBED"))"
    echo

    # --- Post-processing & Metadata
    printf "$category_format" "Metadata & Post-processing"
    printf "$setting_format" 5 "Embed Metadata" "$(bool_to_human "$STATE_EMBED_METADATA")"
    printf "$setting_format" 5 "Embed Thumbnail" "$(bool_to_human "$STATE_EMBED_THUMBNAIL")"
    printf "$setting_format" 5 "Write Comments File" "$(bool_to_human "$STATE_WRITE_COMMENTS")"
    echo

    # --- Behavior
    printf "$category_format" "Behavior"
    printf "$setting_format" 6 "SponsorBlock" "${STATE_SPONSORBLOCK_OP}"
    printf "$setting_format" 7 "Save Playlist Order" "$(bool_to_human "$STATE_SAVE_PLAYLIST_ORDER")"
    printf "$setting_format" 7 "Ignore Errors" "$(bool_to_human "$STATE_IGNORE_ERRORS")"
    echo

    echo " s - Save and Finalize"
    echo " q - Quit without saving"
    echo
}

edit_path() { prompt_for_download_path; }

edit_output_template() {
    clear
    echo -e "${B_BLUE}--- Filename Template Wizard ---${NC}"
    echo "Current: '${STATE_OUTPUT_TEMPLATE}'"
    echo
    echo "Choose a preset or build a custom one."
    echo " 1. Uploader - Title [ID]"
    echo " 2. Title - Uploader [ID]"
    echo " 3. Playlist Index - Title [ID]"
    echo " c. Custom..."
    printf "> "
    read -r -n 1 choice
    echo

    case "$choice" in
        1) STATE_OUTPUT_TEMPLATE='%(uploader)s - %(title)s [%(id)s].%(ext)s' ;;
        2) STATE_OUTPUT_TEMPLATE='%(title)s - %(uploader)s [%(id)s].%(ext)s' ;;
        3) STATE_OUTPUT_TEMPLATE='%(playlist_index)s - %(title)s [%(id)s].%(ext)s' ;;
        c) printf "Enter custom template string:\n> "; read -r STATE_OUTPUT_TEMPLATE ;;
        *) echo "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

edit_primary_use_case() {
    prompt_for_use_case
    if [[ "$STATE_USE_CASE" == "video" ]]; then
        prompt_for_resolution
    else
        prompt_for_audio_format
    fi
}

edit_subtitles() {
    clear
    echo -e "${B_BLUE}--- Subtitle Settings ---${NC}"
    echo " 1. Toggle Subtitles       ($(bool_to_human "$STATE_SUB_WANT"))"
    echo " 2. Change Languages       (${STATE_SUB_LANGS})"
    echo " 3. Toggle Embed/File      ($(if [[ "$STATE_SUB_EMBED" == 1 ]]; then echo "Embed"; else echo "Separate File"; fi))"
    echo " 4. Toggle Auto-subs       ($(bool_to_human "$STATE_SUB_AUTO"))"
    echo " b. Back"
    printf "> "
    read -r -n 1 choice
    echo

    case "$choice" in
        1) ((STATE_SUB_WANT = !STATE_SUB_WANT)) ;;
        2) select_subtitle_languages ;;
        3) ((STATE_SUB_EMBED = !STATE_SUB_EMBED)) ;;
        4) ((STATE_SUB_AUTO = !STATE_SUB_AUTO)) ;;
        b) return ;;
        *) echo "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

edit_metadata_toggles() {
    clear
    echo -e "${B_BLUE}--- Metadata & Post-processing ---${NC}"
    echo " 1. Toggle Embed Metadata  ($(bool_to_human "$STATE_EMBED_METADATA"))"
    echo " 2. Toggle Embed Thumbnail ($(bool_to_human "$STATE_EMBED_THUMBNAIL"))"
    echo " 3. Toggle Write Comments  ($(bool_to_human "$STATE_WRITE_COMMENTS"))"
    echo " b. Back"
    printf "> "
    read -r -n 1 choice
    echo

    case "$choice" in
        1) ((STATE_EMBED_METADATA = !STATE_EMBED_METADATA)) ;;
        2) ((STATE_EMBED_THUMBNAIL = !STATE_EMBED_THUMBNAIL)) ;;
        3) ((STATE_WRITE_COMMENTS = !STATE_WRITE_COMMENTS)) ;;
        b) return ;;
        *) echo "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

edit_sponsorblock() {
    clear
    echo -e "${B_BLUE}--- SponsorBlock Settings ---${NC}"
    echo " 1. Off"
    echo " 2. Mark segments (doesn't remove)"
    echo " 3. Remove segments (default categories)"
    echo " 4. Remove segments (all categories)"
    printf "> "
    read -r -n 1 choice
    echo

    case "$choice" in
        1) STATE_SPONSORBLOCK_OP="--no-sponsorblock" ;;
        2) STATE_SPONSORBLOCK_OP="--sponsorblock-mark all" ;;
        3) STATE_SPONSORBLOCK_OP="--sponsorblock-remove sponsor,selfpromo" ;;
        4) STATE_SPONSORBLOCK_OP="--sponsorblock-remove all" ;;
        *) echo "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}

edit_playlist_and_error() {
    clear
    echo -e "${B_BLUE}--- Behavior Settings ---${NC}"
    echo " 1. Toggle Save Playlist Order ($(bool_to_human "$STATE_SAVE_PLAYLIST_ORDER"))"
    echo " 2. Toggle Ignore Errors       ($(bool_to_human "$STATE_IGNORE_ERRORS"))"
    echo " b. Back"
    printf "> "
    read -r -n 1 choice
    echo

    case "$choice" in
        1) ((STATE_SAVE_PLAYLIST_ORDER = !STATE_SAVE_PLAYLIST_ORDER)) ;;
        2) ((STATE_IGNORE_ERRORS = !STATE_IGNORE_ERRORS)) ;;
        b) return ;;
        *) echo "${RED}Invalid selection.${NC}"; sleep 1 ;;
    esac
}


# ==============================================================================
# --- FINALIZATION & UTILITIES ---
# ==============================================================================

generate_config_string() {
    local conf=""
    conf+="# Generated by yt-dlp Configuration Wizard\n"
    conf+="# $(date)\n\n"

    # --- Paths and Naming ---
    conf+="# === Paths and Naming ===\n"
    [[ -n "$STATE_DL_PATH" ]] && conf+="--paths \"$STATE_DL_PATH\"\n"
    [[ -n "$STATE_OUTPUT_TEMPLATE" ]] && conf+="-o \"$STATE_OUTPUT_TEMPLATE\"\n\n"

    # --- Format Selection ---
    conf+="# === Format Selection ===\n"
    if [[ "$STATE_USE_CASE" == "video" ]]; then
        conf+="--format-sort \"$STATE_RESOLUTION_SORTER\"\n"
    else
        conf+="--extract-audio\n"
        conf+="--audio-format $STATE_AUDIO_FORMAT\n"
        conf+="--audio-quality 0\n"
    fi
    if [[ "$STATE_SUB_WANT" == 1 ]]; then
        conf+="# -- Subtitles --\n"
        [[ "$STATE_SUB_AUTO" == 1 ]] && conf+="--write-auto-subs\n"
        [[ "$STATE_SUB_EMBED" == 1 ]] && conf+="--embed-subs\n" || conf+="--write-subs\n"
        conf+="--sub-langs \"${STATE_SUB_LANGS}\"\n"
    fi
    conf+="\n"

    # --- Post-processing ---
    conf+="# === Post-processing ===\n"
    [[ "$STATE_EMBED_METADATA" == 1 ]] && conf+="--embed-metadata\n" || conf+="--no-embed-metadata\n"
    [[ "$STATE_EMBED_THUMBNAIL" == 1 ]] && conf+="--embed-thumbnail\n" || conf+="--no-embed-thumbnail\n"
    [[ "$STATE_WRITE_COMMENTS" == 1 ]] && conf+="--write-comments\n"
    conf+="\n"

    # --- Behavior ---
    conf+="# === Behavior ===\n"
    [[ -n "$STATE_SPONSORBLOCK_OP" ]] && conf+="$STATE_SPONSORBLOCK_OP\n"
    [[ "$STATE_IGNORE_ERRORS" == 1 ]] && conf+="--ignore-errors\n" || conf+="--no-ignore-errors\n"
    [[ "$STATE_SAVE_PLAYLIST_ORDER" == 0 ]] && conf+="--playlist-reverse\n"

    echo -e "$conf"
}

# ==============================================================================
# --- MAIN MENU & SCRIPT ENTRY ---
# ==============================================================================
main_menu() {
    while true; do
        clear
        echo -e "${B_WHITE}yt-dlp Configuration Wizard${NC}"
        echo "--------------------------"
        echo "1 - Start New Configuration"
        echo "2 - Edit Existing Configuration (${CONFIG_FILE})"
        echo "3 - Exit"
        echo "--------------------------"
        printf "${B_WHITE}Choice: ${NC}"
        read -r -n 1 choice
        echo

        case "$choice" in
            1)
                initialize_state
                run_initial_questionnaire
                run_review_and_edit_loop
                ;;
            2)
                if load_existing_config; then
                    run_review_and_edit_loop
                fi
                ;;
            3)
                echo "Exiting."
                exit 0
                ;;
            *)
                printf "${RED}Invalid option: '%s'${NC}\n" "$choice"
                sleep 1
                ;;
        esac
    done
}

# --- SCRIPT ENTRY ---
main_menu

exit 0