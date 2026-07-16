#!/bin/bash

# --- CONSTANTS & CONFIGURATION ---
set -o pipefail

# Source the master environment file. Defines WORK_DIR, VENV_PYTHON, YTDLP_COMMAND.
SCRIPT_DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" >/dev/null && pwd)"
source "$SCRIPT_DIR/../lib/environment.sh"

# Paths
CONFIG_DIR="$WORK_DIR/config"
MAIN_CONFIG="$CONFIG_DIR/metadata-package.cfg"
STATE_FILE="$CONFIG_DIR/MetadataSelection.state"

# Colors
NC='\e[0m'
GREEN='\e[0;32m'
B_GREEN='\e[1;32m'
B_WHITE='\e[1;37m'
YELLOW='\e[0;33m'
B_BLUE='\e[1;34m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
RED='\e[0;31m'
B_RED='\e[1;31m'
GRAY='\e[1;30m'

# --- DEFAULT SETTINGS ---
# Download
opt_dl_comments=true
opt_dl_transcription=true
opt_dl_description=true
opt_dl_metadata=true

# Multiple URL
opt_run_sequentially=true

# Output
opt_format_json=true
opt_one_file_per_url=true
opt_one_file_all_urls=false
all_urls_filename="combined_archive"
opt_intro_statement=""
opt_non_persistent_intro=true
output_folder=""

# Options
opt_no_sticky=false
opt_no_save_this_run=false

# Internal State
declare -a target_urls

# --- PRE-FLIGHT ---
if ! command -v jq &> /dev/null; then echo "[yt-menu] Error: 'jq' command not found." >&2; exit 1; fi
if ! command -v realpath &> /dev/null; then echo "[yt-menu] Error: 'realpath' command not found." >&2; exit 1; fi

# --- FUNCTIONS ---

format_path() {
    local p="$1"
    if [ ${#p} -gt 12 ]; then
        echo "...${p: -12}"
    else
        echo "$p"
    fi
}

format_intro() {
    local i="$1"
    if [ ${#i} -gt 24 ]; then
        echo "${i:0:24}..."
    else
        echo "$i"
    fi
}

save_sticky_state() {
    if [ "$opt_no_save_this_run" = true ]; then return; fi
    if [ "$opt_no_sticky" = true ]; then
        > "$STATE_FILE"
        return
    fi

    : > "$STATE_FILE"
    echo "opt_dl_comments=$opt_dl_comments" >> "$STATE_FILE"
    echo "opt_dl_transcription=$opt_dl_transcription" >> "$STATE_FILE"
    echo "opt_dl_description=$opt_dl_description" >> "$STATE_FILE"
    echo "opt_dl_metadata=$opt_dl_metadata" >> "$STATE_FILE"
    echo "opt_one_file_per_url=$opt_one_file_per_url" >> "$STATE_FILE"
    echo "opt_one_file_all_urls=$opt_one_file_all_urls" >> "$STATE_FILE"
    echo "all_urls_filename=$all_urls_filename" >> "$STATE_FILE"
    echo "opt_non_persistent_intro=$opt_non_persistent_intro" >> "$STATE_FILE"

    # Only save Intro Statement if non-persistent is OFF
    if [ "$opt_non_persistent_intro" = false ]; then
        echo "opt_intro_statement=$(echo -n "$opt_intro_statement" | base64 -w 0)" >> "$STATE_FILE"
    fi
}

load_sticky_state() {
    if [ -f "$STATE_FILE" ]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            if [[ "$key" == "opt_intro_statement" ]]; then
                opt_intro_statement=$(echo -n "$value" | base64 -d)
            else
                declare -g "$key=$value"
            fi
        done < "$STATE_FILE"
    fi
}

update_config_file() {
    echo "OUTPUT_FOLDER=\"$output_folder\"" > "$MAIN_CONFIG"
}

display_menu() {
    local state="$1"
    clear
    echo -e "\n${B_WHITE}--- METADATA-PACKAGE Menu ---${NC}"
    
    if [ "$state" == "locked" ]; then
        echo -e "\n Paste URL, local file path, or type 'list' to edit.\n"
    else
        echo -e " Edit settings for archival package generation.\n"
        if [ ${#target_urls[@]} -eq 1 ]; then
            echo -e "${YELLOW}Target:${NC} ${target_urls[0]}"
        elif [ ${#target_urls[@]} -gt 1 ]; then
            echo -e "${YELLOW}Target:${NC} ${#target_urls[@]} URLs loaded"
        fi
        echo ""
    fi

    render_item() {
        local hotkey="$1"
        local var_val="$2"
        local desc="$3"
        local is_grayed="$4"
        
        local status="[ ]"
        [[ "$var_val" == true ]] && status="[x]"

        if [ "$is_grayed" == true ]; then
            printf " ${GRAY}%s %s %s${NC}\n" "$hotkey." "$status" "$desc"
        elif [ "$state" == "locked" ]; then
            printf " ${GRAY}%s %s %s${NC}\n" "$hotkey." "$status" "$desc"
        else
            [[ "$var_val" == true ]] && status="[${GREEN}x${NC}]"
            printf " %s %b ${B_WHITE}%s${NC}\n" "$hotkey." "$status" "$desc"
        fi
    }

    echo -e "${CYAN}_Download_${NC}"
    render_item "1" "$opt_dl_comments" "Comments" false
    render_item "2" "$opt_dl_transcription" "Transcription" false
    render_item "3" "$opt_dl_description" "Description" false
    render_item "4" "$opt_dl_metadata" "Metadata" false
    echo ""
    
    echo -e "${CYAN}_Multiple URL_${NC}"
    render_item "s" "$opt_run_sequentially" "Run sequentially" false
    render_item "c" "false" "Run concurrently [AWAITING IMPLEMENTATION]" true
    render_item "n" "false" "Set number of concurrent instances [AWAITING IMPLEMENTATION]" true
    echo ""
    
    echo -e "${CYAN}_Output_${NC}"
    render_item "m" "false" "Format: .md Markdown [AWAITING IMPLEMENTATION]" true
    render_item "j" "$opt_format_json" "Format: .json" false
    render_item "t" "false" "Format: .txt Plain text [AWAITING IMPLEMENTATION]" true
    
    local folder_display=$(format_path "$output_folder")
    if [ "$state" == "locked" ]; then
        printf " ${GRAY}o. [ ] Set output folder: %s${NC}\n" "$folder_display"
    else
        printf " o. [ ] ${B_WHITE}Set output folder: %s${NC}\n" "$folder_display"
    fi

    render_item "p" "$opt_one_file_per_url" "One output .package per each URL" false
    
    local all_urls_desc="One .package per all URLs."
    if [ "$opt_one_file_all_urls" == true ]; then all_urls_desc+=" ($all_urls_filename)"; fi
    render_item "a" "$opt_one_file_all_urls" "$all_urls_desc" false
    
    local intro_disp=$(format_intro "$opt_intro_statement")
    local has_intro=false; [[ -n "$opt_intro_statement" ]] && has_intro=true
    if [ "$state" == "locked" ]; then
        printf " ${GRAY}i. %s Set introductory statement: %s${NC}\n" "$([[ $has_intro == true ]] && echo "[x]" || echo "[ ]")" "$intro_disp"
    else
        printf " i. %b ${B_WHITE}Set introductory statement: %s${NC}\n" "$([[ $has_intro == true ]] && echo "[${GREEN}x${NC}]" || echo "[ ]")" "$intro_disp"
    fi
    
    render_item "x" "$opt_non_persistent_intro" "Non Persistent introductory statement" false
    echo ""

    echo -e "${CYAN}_Options_${NC}"
    render_item "d" "$opt_no_sticky" "Disable Sticky Settings." false
    render_item "u" "$opt_no_save_this_run" "Don't update Sticky Settings state from this run." false
    echo ""

    if [[ "$state" == "active" ]]; then
        echo -e "${B_BLUE} Enter Hotkey to toggle, or ${B_WHITE}+${B_BLUE} to Run${NC}"
        echo ""
        printf " %s %b\n" "f." "${B_WHITE}Re-enter URL(s)..${NC}"
        echo ""
    fi
}

# --- 1. Load Configuration ---
if [ ! -d "$CONFIG_DIR" ]; then mkdir -p "$CONFIG_DIR"; fi
if [ -f "$MAIN_CONFIG" ]; then
    source "$MAIN_CONFIG"
    output_folder="$OUTPUT_FOLDER"
fi

if [ -z "$output_folder" ]; then
    if [ -t 0 ]; then
        echo "[yt-menu] Config ($MAIN_CONFIG) missing or OUTPUT_FOLDER not set."
        while [ -z "$output_folder" ]; do
            printf "Enter your desired output folder for metadata packages: "
            read -e -r output_folder
            if [ -z "$output_folder" ]; then echo "[yt-menu] Path cannot be empty."; fi
        done
        output_folder=$(realpath "$output_folder" 2>/dev/null || echo "$output_folder")
        if [ ! -d "$output_folder" ]; then mkdir -p "$output_folder"; fi
        update_config_file
        echo "[yt-menu] Configuration saved."
    else
        echo "[yt-menu] Error: Output directory not configured. Exit." >&2; exit 1
    fi
fi

load_sticky_state

# --- 3. INTERFACE LOOP ---

target_urls=()

while true; do
    if [ ${#target_urls[@]} -eq 0 ]; then
        # === STATE 1: LOCKED / PASTE MODE ===
        display_menu "locked"
        echo -e "\n${B_GREEN}Paste URL, local file path, or type 'list' to paste multiple URLs:${NC}"
        tput cuu 1; tput cuf 65
        read -e -r url_input
        
        if [ -z "$url_input" ]; then continue; fi
        
        if [[ "${url_input,,}" == "list" ]]; then
            echo -e "\n${YELLOW}Enter/Paste URLs (Submit an empty line or type 'EOF' to finish):${NC}"
            while IFS= read -r line; do
                line=$(echo "$line" | xargs)
                [[ -z "$line" || "$line" == "EOF" ]] && break
                target_urls+=("$line")
            done
        elif [ -f "$url_input" ]; then
            echo -e "\n${BLUE}Loading URLs from file: $url_input${NC}"
            while IFS= read -r line || [ -n "$line" ]; do
                line=$(echo "$line" | xargs)
                [[ -n "$line" ]] && target_urls+=("$line")
            done < "$url_input"
        else
            target_urls=("$url_input")
        fi

        if [ ${#target_urls[@]} -eq 0 ]; then
            echo "No URLs provided." >&2; sleep 1; continue
        fi
    else
        # === STATE 2: ACTIVE / MENU MODE ===
        display_menu "active"
        printf "${B_WHITE}Choice: ${NC}"
        
        read -r -n 1 input_char || break
        
        if [[ "$input_char" == "+" ]]; then break; fi
        if [[ "$input_char" == "f" || "$input_char" == "F" ]]; then target_urls=(); continue; fi
        
        # Download Toggles
        if [[ "$input_char" == "1" ]]; then opt_dl_comments=$([[ "$opt_dl_comments" == true ]] && echo false || echo true); fi
        if [[ "$input_char" == "2" ]]; then opt_dl_transcription=$([[ "$opt_dl_transcription" == true ]] && echo false || echo true); fi
        if [[ "$input_char" == "3" ]]; then opt_dl_description=$([[ "$opt_dl_description" == true ]] && echo false || echo true); fi
        if [[ "$input_char" == "4" ]]; then opt_dl_metadata=$([[ "$opt_dl_metadata" == true ]] && echo false || echo true); fi
        
        # Multiple URL Toggles
        if [[ "$input_char" == "s" || "$input_char" == "S" ]]; then opt_run_sequentially=true; fi
        
        # Output Toggles
        if [[ "$input_char" == "j" || "$input_char" == "J" ]]; then opt_format_json=true; fi 
        
        if [[ "$input_char" == "o" || "$input_char" == "O" ]]; then
            echo -e "\n${YELLOW}Enter new output folder path:${NC}"
            read -e -r new_folder
            if [ -n "$new_folder" ]; then
                output_folder=$(realpath "$new_folder" 2>/dev/null || echo "$new_folder")
                if [ ! -d "$output_folder" ]; then mkdir -p "$output_folder"; fi
                update_config_file
            fi
        fi
        
        if [[ "$input_char" == "p" || "$input_char" == "P" ]]; then 
            opt_one_file_per_url=true; opt_one_file_all_urls=false
        fi
        
        if [[ "$input_char" == "a" || "$input_char" == "A" ]]; then
            opt_one_file_all_urls=true; opt_one_file_per_url=false
            echo -e "\n${YELLOW}Enter filename for combined package (without extension):${NC}"
            read -e -r new_name
            if [ -n "$new_name" ]; then all_urls_filename="$new_name"; fi
        fi
        
        if [[ "$input_char" == "i" || "$input_char" == "I" ]]; then
            echo -e "\n${B_WHITE}Enter introductory statement (End with 'EOF' on new line):${NC}"
            buffer=""
            while IFS= read -r line; do [[ "$line" == "EOF" ]] && break; buffer+="${line}"$'\n'; done
            if [ -n "${buffer%$'\n'}" ]; then opt_intro_statement="${buffer%$'\n'}"; else opt_intro_statement=""; fi
        fi
        
        if [[ "$input_char" == "x" || "$input_char" == "X" ]]; then opt_non_persistent_intro=$([[ "$opt_non_persistent_intro" == true ]] && echo false || echo true); fi
        
        # Options Toggles
        if [[ "$input_char" == "d" || "$input_char" == "D" ]]; then opt_no_sticky=$([[ "$opt_no_sticky" == true ]] && echo false || echo true); fi
        if [[ "$input_char" == "u" || "$input_char" == "U" ]]; then opt_no_save_this_run=$([[ "$opt_no_save_this_run" == true ]] && echo false || echo true); fi

    fi
done

save_sticky_state

echo -e "\n[yt-menu] -----------------------------------------------------"
echo "[yt-menu] Initializing Archival Metadata Generation..."

# PLAYLIST EXPANSION PHASE
echo "[yt-menu] Expanding playlists and validating URLs..."
declare -a final_target_urls
for url in "${target_urls[@]}"; do
    # yt-dlp --flat-playlist prints the URL(s) without downloading media.
    # Single URLs return themselves. Playlists return all enclosed video URLs.
    mapfile -t extracted < <("${YTDLP_COMMAND_ARRAY[@]}" --flat-playlist --print "webpage_url" "$url" 2>/dev/null)
    if [ ${#extracted[@]} -eq 0 ]; then
        final_target_urls+=("$url") # fallback
    else
        for e in "${extracted[@]}"; do
            final_target_urls+=("$e")
        done
    fi
done
target_urls=("${final_target_urls[@]}")
total_urls=${#target_urls[@]}
echo "[yt-menu] Total distinct videos to process: $total_urls"

# TEMP DIRECTORY & CLEANUP
tmp_dir=$(mktemp -d)
trap_error_suppress=0
cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ "$trap_error_suppress" -eq 1 ]; then return; fi
    trap_error_suppress=1
    echo "[yt-menu] -----------------------------------------------------"
    echo -n "[yt-menu] Cleaning up temp files ($tmp_dir)..."
    rm -rf "$tmp_dir"
    echo " Done."
}
trap cleanup EXIT

# JSON COMBINER MEMORY FILE
combined_temp="$tmp_dir/combined_videos.json"
echo "[" > "$combined_temp"
first_combined=true

current_url_index=0

# Start URL Processing Loop
for url in "${target_urls[@]}"; do
    ((current_url_index++))
    echo -e "\n[yt-menu] -----------------------------------------------------"
    echo -e "[yt-menu] ${B_BLUE}Processing $current_url_index/$total_urls:${NC} $url"
    
    vid_tmp="$tmp_dir/vid_$current_url_index"
    mkdir -p "$vid_tmp"
    
    # Phase 1: Download Metadata
    declare -a dl_cmd=("${YTDLP_COMMAND_ARRAY[@]}" --no-playlist)
    
    if [ "$opt_dl_comments" = true ]; then dl_cmd+=(--extractor-args "youtube:comment_sort=top" --write-comments); fi
    if [ "$opt_dl_description" = true ]; then dl_cmd+=(--write-description); fi
    
    dl_cmd+=( --write-info-json --skip-download --ignore-config --paths "$vid_tmp" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url")
    
    "${dl_cmd[@]}"
    if [ $? -ne 0 ]; then echo -e "${RED}[yt-menu] Error: yt-dlp failed for this URL. Skipping.${NC}" >&2; continue; fi

    info_json_file=$(find "$vid_tmp" -name "*.info.json" | head -n 1)
    if [ -z "$info_json_file" ]; then echo -e "${RED}[yt-menu] Error: .info.json not found for this URL. Skipping.${NC}" >&2; continue; fi
    
    base_filename="${info_json_file%.info.json}"
    description_file="$base_filename.description"

    # Phase 2: Transcription
    if [ "$opt_dl_transcription" = true ]; then
        echo "[yt-menu] Analyzing subtitles..."
        mapfile -t available_sub_langs < <(jq -r '(.subtitles // {}) + (.automatic_captions // {}) | keys[]' "$info_json_file" | sort -u)
        original_lang=$(jq -r '.language // "en"' "$info_json_file")
        best_lang_to_download=""
        
        if [ ${#available_sub_langs[@]} -gt 0 ]; then
            for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "$original_lang" ]] && best_lang_to_download="$lang" && break; done
            if [ -z "$best_lang_to_download" ] && [[ "$original_lang" == *-* ]]; then
                primary="${original_lang%%-*}"
                for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "$primary" ]] && best_lang_to_download="$lang" && break; done
            fi
            if [ -z "$best_lang_to_download" ]; then
                for lang in "${available_sub_langs[@]}"; do [[ "$lang" == "en" ]] && best_lang_to_download="$lang" && break; done
            fi
            if [ -z "$best_lang_to_download" ]; then best_lang_to_download="${available_sub_langs[0]}"; fi
            
            if [ -n "$best_lang_to_download" ]; then
                echo "[yt-menu]   -> Downloading subtitle: $best_lang_to_download"
                "${YTDLP_COMMAND_ARRAY[@]}" --no-playlist --write-subs --write-auto-subs --sub-lang "$best_lang_to_download" --sub-format "srt/ass/best" --skip-download --ignore-errors --ignore-config --paths "$vid_tmp" --output "%(channel)s - %(title)s [%(id)s].%(upload_date)s.%(ext)s" "$url" >/dev/null 2>&1
            fi
        fi
    fi

    # Phase 3: Processors
    threaded_comments_file=""
    if [ "$opt_dl_comments" = true ]; then
        echo "[yt-menu] Restructuring comments..."
        python_script_path="$WORK_DIR/libexec/json-restructurer.py"
        threaded_comments_file=$("$VENV_PYTHON" "$python_script_path" "$info_json_file" 2>/dev/null)
    fi

    structured_transcription_file=""
    if [ "$opt_dl_transcription" = true ]; then
        echo "[yt-menu] Processing transcription..."
        best_sub_file=$(find "$vid_tmp" -name "*.srt" -o -name "*.ass" | head -n 1)
        if [ -n "$best_sub_file" ]; then
            case "$best_sub_file" in
                *.srt) processor="$WORK_DIR/libexec/srt-processor.py" ;;
                *.ass) processor="$WORK_DIR/libexec/ass-processor.py" ;;
            esac
            if [ -n "$processor" ]; then
                structured_transcription_file=$("$VENV_PYTHON" "$processor" "$best_sub_file")
            fi
        fi
        if [ -z "$structured_transcription_file" ]; then echo -e "${YELLOW}[yt-menu] Warning: No transcription generated.${NC}"; fi
    fi

    # Phase 4: Assembly for this URL
    echo "[yt-menu] Assembling JSON for URL..."
    
    comment_count="null"
    if [ "$opt_dl_comments" = true ]; then
        comment_count=$(jq -r '(.comments | length) // 0' "$info_json_file")
    fi

    jq_args=( --arg user_url "$url" )
    
    # Root level video descriptors
    jq_filter='{
        title: .title,
        webpage_url: .webpage_url,
        user_supplied_url: $user_url
    }'
    
    if [ "$opt_dl_metadata" = true ]; then
        jq_args+=( --argjson cc "${comment_count:-null}" )
        jq_filter="$jq_filter"' + {
            metadata: {
                id: .id,
                upload_date: .upload_date,
                duration_string: .duration_string,
                uploader: .uploader,
                channel: .channel,
                channel_url: .channel_url,
                channel_follower_count: (.channel_follower_count // null),
                view_count: (.view_count // null),
                like_count: (.like_count // null),
                total_comments: (.comment_count // null),
                extracted_comments: $cc
            }
        }'
    fi
    
    if [ "$opt_dl_description" = true ] && [ -f "$description_file" ]; then
        jq_args+=( --rawfile desc "$description_file" )
        jq_filter="$jq_filter"' + { description: $desc }'
    fi

    if [ "$opt_dl_transcription" = true ] && [ -n "$structured_transcription_file" ]; then
        jq_args+=( --slurpfile trans "$structured_transcription_file" )
        jq_filter="$jq_filter"' + { transcription: $trans[0] }'
    fi

    if [ "$opt_dl_comments" = true ] && [ -n "$threaded_comments_file" ]; then
        jq_args+=( --slurpfile comms "$threaded_comments_file" )
        jq_filter="$jq_filter"' + { comments: $comms[0] }'
    fi

    vid_json_path="$vid_tmp/final_vid.json"
    jq "${jq_args[@]}" "$jq_filter" "$info_json_file" > "$vid_json_path"

    # Save Individual Output
    if [ "$opt_one_file_per_url" = true ]; then
        package_basename=$(basename "${base_filename}.metadata-package.json")
        final_dest="$output_folder/$package_basename"
        
        # Build Standardized Root JSON Schema
        wrap_args=( --arg info "This archival package of metadata was captured using https://github.com/mons8/yt-menu." )
        wrap_filter='{ info: $info }'
        
        if [ -n "$opt_intro_statement" ]; then
            wrap_args+=( --arg intro "$opt_intro_statement" )
            wrap_filter="$wrap_filter"' + { introductory_user_statement: $intro }'
        fi
        
        wrap_args+=( --slurpfile vid "$vid_json_path" )
        wrap_filter="$wrap_filter"' + { videos: $vid }' # slurpfile loads standard object as array of 1
        
        jq "${wrap_args[@]}" "$wrap_filter" <<< "{}" > "$final_dest"
        echo -e "${GREEN}[yt-menu] Saved to: $final_dest${NC}"
    fi

    # Append to combined Memory
    if [ "$opt_one_file_all_urls" = true ]; then
        if [ "$first_combined" = true ]; then
            first_combined=false
        else
            echo "," >> "$combined_temp"
        fi
        cat "$vid_json_path" >> "$combined_temp"
        echo -e "${YELLOW}[yt-menu] Appended to memory/temp for combined package...${NC}"
    fi

done # End of URL Loop

# Phase 5: Finalize Combined Package
if [ "$opt_one_file_all_urls" = true ]; then
    echo "]" >> "$combined_temp" # Close the JSON array we built in the loop
    
    echo -e "\n[yt-menu] -----------------------------------------------------"
    echo "[yt-menu] Finalizing combined archival package..."
    
    final_dest="$output_folder/${all_urls_filename}.metadata-package.json"
    
    # Build Standardized Root JSON Schema
    wrap_args=( --arg info "This archival package of metadata was captured using https://github.com/mons8/yt-menu." )
    wrap_filter='{ info: $info }'
    
    if [ -n "$opt_intro_statement" ]; then
        wrap_args+=( --arg intro "$opt_intro_statement" )
        wrap_filter="$wrap_filter"' + { introductory_user_statement: $intro }'
    fi
    
    wrap_args+=( --slurpfile vids "$combined_temp" )
    wrap_filter="$wrap_filter"' + { videos: $vids[0] }' # slurpfile loads our array into $vids[0]
    
    jq "${wrap_args[@]}" "$wrap_filter" <<< "{}" > "$final_dest"
    
    if [ -s "$final_dest" ]; then
        echo -e "${GREEN}[yt-menu] Successfully created combined package: $final_dest${NC}"
    else
        echo -e "${RED}[yt-menu] Error generating combined package.${NC}" >&2
    fi
fi