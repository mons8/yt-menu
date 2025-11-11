#!/bin/bash

# --- Configuration ---
# Get the absolute path of the script's directory (i.e., the project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
VENDOR_DIR="$PROJECT_ROOT/vendor"
YTDLP_DIR="$VENDOR_DIR/yt-dlp"
FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"

# Colors for output
GREEN='\033[0;32m'
B_RED='\033[1;31m'
B_YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# ---------------------

echo "--- Starting Project Installation ---"

# --- 1. Dependency Checks (git, pip) ---

# Check for git
if ! command -v git &> /dev/null; then
    echo -e "\n${B_RED}ERROR: 'git' not found.${NC}" >&2
    echo "Please install git. E.g., on Debian/Ubuntu: 'sudo apt update && sudo apt install git'"
    echo "URL: https://git-scm.com/downloads"
    exit 1
fi

# Check for python3 and ensure it can run 'venv'
if ! command -v python3 &> /dev/null; then
    echo -e "\n${B_RED}ERROR: 'python3' not found.${NC}" >&2
    echo "Please install Python 3."
    exit 1
fi

# Check for pip (using the python interpreter to be safe)
if ! python3 -m pip --version &> /dev/null; then
    echo -e "\n${B_RED}ERROR: 'pip' (Python package installer) not found.${NC}" >&2
    echo "Please install pip. E.g., on Debian/Ubuntu: 'sudo apt install python3-pip'"
    exit 1
fi

# Check for tar and wget/curl (required for FFmpeg download)
if ! command -v tar &> /dev/null; then
    echo -e "\n${B_RED}ERROR: 'tar' not found. It is needed to extract FFmpeg.${NC}" >&2
    exit 1
fi
DOWNLOAD_CMD=""
if command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -O"
elif command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -L -o"
else
    echo -e "\n${B_RED}ERROR: Neither 'wget' nor 'curl' found. One is needed to download FFmpeg.${NC}" >&2
    exit 1
fi


# --- 2. Setup VENV ---
echo -e "\n--- Creating Virtual Environment ---"
if [ -d "$VENV_DIR" ]; then
    echo "Virtual environment already exists. Deleting and recreating..."
    rm -rf "$VENV_DIR"
fi
python3 -m venv "$VENV_DIR"

# Define the venv-specific Python and pip executables
VENV_PYTHON="$VENV_DIR/bin/python3"
VENV_PIP="$VENV_DIR/bin/pip"
VENV_ACTIVATE=". $VENV_DIR/bin/activate"

# Ensure pip is up to date inside the venv
echo "Upgrading pip and setuptools in venv..."
$VENV_PIP install --upgrade pip setuptools

# --- 3. Clone yt-dlp ---
echo -e "\n--- Cloning yt-dlp into $YTDLP_DIR ---"
mkdir -p "$VENDOR_DIR"
if [ -d "$YTDLP_DIR" ]; then
    echo "yt-dlp directory already exists. Pulling latest changes..."
    git -C "$YTDLP_DIR" pull
else
    git clone https://github.com/yt-dlp/yt-dlp.git "$YTDLP_DIR"
fi

# --- 4. Download and Install FFmpeg/FFprobe Binaries ---
echo -e "\n--- Downloading and Extracting FFmpeg/FFprobe ---"
FFMPEG_ARCHIVE="$PROJECT_ROOT/ffmpeg-archive.tar.xz"

# Download the archive
$DOWNLOAD_CMD "$FFMPEG_ARCHIVE" "$FFMPEG_URL"
if [ $? -ne 0 ]; then
    echo -e "\n${B_RED}ERROR: Failed to download FFmpeg binaries.${NC}" >&2
    exit 1
fi

# Extract only the necessary binaries to the yt-dlp vendor directory
# NOTE: yt-dlp checks for ffmpeg/ffprobe in the same directory as its own executable.
tar -xf "$FFMPEG_ARCHIVE" --strip-components=2 -C "$YTDLP_DIR" \
    "ffmpeg-master-latest-linux64-gpl/bin/ffmpeg" \
    "ffmpeg-master-latest-linux64-gpl/bin/ffprobe"

# Make sure they are executable
chmod +x "$YTDLP_DIR/ffmpeg" "$YTDLP_DIR/ffprobe"

# Clean up the archive
rm "$FFMPEG_ARCHIVE"

## FFmpeg GPL compliance at end of script

# --- 5. Python Dependencies ---
echo -e "\n--- Installing Python Dependencies (requests, playwright, curl_cffi) ---"
$VENV_PIP install --upgrade requests curl_cffi playwright

# Playwright Browsers
echo "Running Playwright's browser installation (this may take a moment)..."
$VENV_PYTHON -m playwright install

# --- 5.5 Optional System-Wide Tools (jq, deno) ---
echo -e "\n--- Optional System-Wide Tools ---"
read -p "$(echo -e "${B_YELLOW}jq and deno must be installed system-wide for optimal functioning of yt-menu and yt-dlp, respectively. Proceed? [y/N] ${NC}")" response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "\nProceeding with optional installations..."

    # --- Install jq ---
    echo -e "\n--- Checking for jq ---"
    if command -v jq &> /dev/null; then
        echo "jq is already installed."
    else
        if command -v apt &> /dev/null; then
            echo "Attempting to install jq using apt. You may be prompted for your password."
            sudo apt update && sudo apt install -y jq
        else
            echo -e "${B_YELLOW}'apt' not found. Please install 'jq' manually with your systems package manager.${NC}"
            echo -e "${B_YELLOW} 'jq' is necessary for advanced metadata processing.${NC}"
        fi
    fi

    # --- Install deno ---
    echo -e "\n--- Checking for deno ---"
    if command -v deno &> /dev/null; then
        echo "deno is already installed."
    else
        echo "Attempting to install deno..."
        echo -e "${B_YELLOW}The Deno installer is ${B_RED}interactive, ${B_YELLOW}Please follow its prompts.${NC}"
        curl -fsSL https://deno.land/install.sh | sh
    fi

else
    echo -e "\nSkipping installation of optional system-wide tools."
    echo -e "${B_YELLOW}Note: 'jq' is necessary for advanced metadata processing and 'deno' is required for full yt-dlp functionality.${NC}"
fi

# GPL Compliance: Build log infom, which constitutes the "written offer for source"
echo "Fetching release information for GPL compliance..."

FILENAME=$(curl -sL "https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases" | \
jq -r '
  [.[] | select(.tag_name != "latest")][0].assets |
  .[] | select(.name | test("linux64-gpl.tar.xz$")).name
')

if [ -z "$FILENAME" ]; then
    echo -e "\n${B_RED}ERROR: Could not determine FFmpeg build filename from GitHub API.${NC}" >&2
    exit 1
fi

COMMIT_HASH=$(echo "$FILENAME" | grep -oP 'g[0-9a-fA-F]+' | head -n 1)

if [ -z "$COMMIT_HASH" ]; then
    echo -e "\n${B_RED}ERROR: Could not extract commit hash from filename: $FILENAME${NC}" >&2
    exit 1
fi

# Write the complete, two-part compliance notice.
cat > "$FFMPEG_COMPLIANCE_DIR/build_and_source_info.txt" << EOF
This software utilizes FFmpeg binaries distributed under the GPLv3.

The "Corresponding Source" is provided in two parts:

1. THE FFMPEG SOURCE CODE:
The binaries were built from the FFmpeg source code identified by the git commit hash
contained within the build name:

$FILENAME

The source can be obtained by cloning the official FFmpeg git
repository (git://source.ffmpeg.org/ffmpeg.git) and checking out the commit
'$COMMIT_HASH'.

2. THE BUILD SCRIPTS AND CONFIGURATION:
The scripts and configuration flags used to compile the source code are available at
the repository responsible for this build:

https://github.com/yt-dlp/FFmpeg-Builds

EOF

# User-facing notice to be precise
echo -e "\n${B_GREEN}GPL COMPLIANCE NOTICE:${NC}"
echo "This software uses FFmpeg binaries licensed under the GPLv3."
echo "The FFmpeg license, documentation and build log containing instructions"
echo "to retrieve the complete corresponding source code are saved to:"
echo "    $FFMPEG_COMPLIANCE_DIR"
echo "This is required for you to legally use and redistribute this software."

if [ $? -eq 0 ]; then
    echo "GPL compliance information successfully saved."
else
    echo -e "\n${B_RED}ERROR: Failed to write GPL compliance file.${NC}" >&2
    exit 1
fi

# --- 6. Final Steps ---
echo -e "\n--- Installation Complete ---"
echo "Run yt-menu by:"
echo -e "    ${GREEN}./bin/yt-menu${NC}"

exit 0
