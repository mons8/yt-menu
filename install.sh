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



# --- Configuration ---
# Get the absolute path of the script's directory (i.e., the project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
VENDOR_DIR="$PROJECT_ROOT/vendor"
YTDLP_DIR="$VENDOR_DIR/yt-dlp"
FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
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

# --- 4. Download and Install FFmpeg/FFprobe Binaries (GPL Compliant) ---
echo -e "\n--- Downloading and Extracting FFmpeg/FFprobe ---"
FFMPEG_ARCHIVE_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
FFMPEG_LOG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.log"

FFMPEG_ARCHIVE_PATH="$PROJECT_ROOT/ffmpeg-archive.tar.xz"
FFMPEG_COMPLIANCE_DIR="$PROJECT_ROOT/ffmpeg_gpl_materials"

# Create the compliance directory upfront
mkdir -p "$FFMPEG_COMPLIANCE_DIR"

# Download the archive
$DOWNLOAD_CMD "$FFMPEG_ARCHIVE_PATH" "$FFMPEG_ARCHIVE_URL"
if [ $? -ne 0 ]; then
    echo -e "\n${B_RED}ERROR: Failed to download FFmpeg binaries.${NC}" >&2
    exit 1
fi

# Download the corresponding build log, which constitutes the "written offer for source"
echo "Downloading FFmpeg build log for GPL compliance..."
$DOWNLOAD_CMD "$FFMPEG_COMPLIANCE_DIR/build.log" "$FFMPEG_LOG_URL"
if [ $? -ne 0 ]; then
    echo -e "\n${B_RED}ERROR: Failed to download FFmpeg build log. Cannot ensure GPL compliance.${NC}" >&2
    exit 1
fi

# Extract the entire contents of the archive to the compliance directory
echo "Extracting FFmpeg package..."
tar -xf "$FFMPEG_ARCHIVE_PATH" --strip-components=1 -C "$FFMPEG_COMPLIANCE_DIR"
rm "$FFMPEG_ARCHIVE_PATH" # Clean up the archive

# Move the FFmpeg binaries to the location yt-dlp expects
echo "Placing binaries in vendor directory..."
mv "$FFMPEG_COMPLIANCE_DIR/bin/ffmpeg" "$YTDLP_DIR/ffmpeg"
mv "$FFMPEG_COMPLIANCE_DIR/bin/ffprobe" "$YTDLP_DIR/ffprobe"
chmod +x "$YTDLP_DIR/ffmpeg" "$YTDLP_DIR/ffprobe"

# Clean up the now-unneeded bin directory from the compliance materials
rm -rf "$FFMPEG_COMPLIANCE_DIR/bin"

# Update the user-facing notice to be precise
echo -e "\n${B_GREEN}GPL COMPLIANCE NOTICE:${NC}"
echo "This software uses FFmpeg binaries licensed under the GPLv3."
echo "The FFmpeg license, documentation and build log containing instructions"
echo "to retrieve the complete corresponding source code are saved to:"
echo "    $FFMPEG_COMPLIANCE_DIR"
echo "This is required for you to legally use and redistribute this software."

# --- 5. Install Python Dependencies ---
echo -e "\n--- Installing Python Dependencies (requests, playwright, curl_cffi) ---"
$VENV_PIP install --upgrade requests curl_cffi playwright

# CRITICAL: Install Playwright Browsers
# Playwright needs to download browser binaries *after* installation.
echo "Running Playwright's browser installation (this may take a moment)..."
$VENV_PYTHON -m playwright install

# --- 6. Final Steps ---
echo -e "\n--- Installation Complete ---"
echo "To begin using the scripts, activate the venv and run yt-menu:"
echo -e "    ${GREEN}. .venv/bin/activate${NC}"
echo -e "    ${GREEN}./bin/yt-menu${NC}"

exit 0
