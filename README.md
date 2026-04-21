# yt-menu
**Audio and Video Archival** and **LLM Context Packages**.

`yt-menu` is a power-user TUI built on top of `yt-dlp`. It minimizes clicks for anyone that likes to archive online content. 

Notably, it also features a _powerful_ methodology for facilitating AI-assisted analysis with the `llm-package` generator. This little tool does two things:
1. Conveniently converts online videos, comments and metadata into a single, human-and-machine-readable and token-conscious JSON dataset for feeding _contextual RAG-adjacent packages_ to Large Language Models
2. Allows for injecting pre-set or custom prompts into the same dataset file for maximally quick, complete and competent analysis.

It installs all dependencies such as `FFmpeg` and `yt-dlp` quickly and easily with an installer script and uses a `venv` virtual envionment for all Python dependencies to avoid contaminating the main system with strange Python packages.

---
<img width="809" height="339" alt="20260106_230800" src="https://github.com/user-attachments/assets/bab97c26-2ebb-4cfe-b97c-694be26ade94" />

_Main menu_

<img width="809" height="493" alt="prompt-injection" src="https://github.com/user-attachments/assets/c1a86478-85b4-4e1e-b413-4f6881429478" />

_Prompt Injection_

---
## Core Capabilities


### `llm-package`, AI-Context Pipeline 

*   **Utility:** Turns a video, comments & metadata into a **knowledge packet** for AI analysis.
*   **Token Conscious:** The output is a single, minimized `.json` file ready to be pasted into a chat window or used for RAG (Retrieval-Augmented Generation).
*   **Clipboard:** The final package path (or content) is automatically copied to clipboard for immediate use and saved in a user-choice directory.
*   **Prompt Injection:** A one-press TUI menu allows you to inject modular instructions directly into the payload. Your choices are then injected directly into the final JSON payload. 
	*   *Extensible:* The menu is built dynamically from the `prompts/` directory. It's preloaded with sensible prompts and you can add or edit categories and prompts by simply creating folders and files in that directory.
    *   *Custom Prompts:* Select <kbd>Custom</kbd> quickly to add ad-hoc prompts on the fly.
	*   *Flexible Downloads:* Toggle <kbd>o</kbd> in the menu to **omit comments**, downloading only the transcription and metadata to save bandwidth and tokens.
*   **Rich Payload:** In addition to <kbd>prompts</kbd> and <kbd>metadata</kbd>, the `JSON` package contains:
    *   *<kbd>Transcription:</kbd>* Auto-selects the best available transcription (human-written and native language) and processes it into a readable and token sensitive format.
    *   *<kbd>Comments:</kbd>* Restructures flat comment dumps into human-and-AI-readable conversation threads for analysis and public reception context. This process prunes out _a lot_ of unneeded and detrimental tokens from the API output.

### Archival
Convenient tools for hoarders and archivists.
*   **Album & Channel Scraping:** Automates the downloading of video content to audio (to mp3) via Channel `/releases` dynamic scraping.
*   **Metadata Tagging:** Automatically applies `ID3` tags and filenaming conventions.
*   **Split Workflows:** Dedicated modes for <kbd>Songs</kbd>, <kbd>Albums</kbd>, or entire <kbd>Channel Discographies</kbd>.
*   **Download Directories:** Customize download folders per mode.
*   **Normal yt-dlp interface:** Allows for normal video download & editing of yt-dlp config file.

## Key Features

-   **Menu-Driven TUI:** Streamlined, low-click interactive interface.
-   **Self-Contained Ecosystem:**
    -   **Isolated Python:** Uses a local `.venv` to manage dependencies (`playwright`, `requests`) without touching your system Python.
    -   **Vendor Management:** Downloads its own local binaries for `yt-dlp` and `ffmpeg` (compliant builds) and other dependencies on install.

## Global requirements for installation

-   A `bash` shell
-   `git`
-   `python3` (with `venv` and `pip`)
-   `curl` or `wget`
-   `tar`
-   `jq` (required for `llm-package` `JSON` processing)

## Installation

The installation process is fully automated.

1.  **Clone repository and run install script**
    ```bash
    git clone https://github.com/mons8/yt-menu.git
    cd yt-menu
    chmod +x install.sh
    ./install.sh
    ```
    
    The script will:
    - Create a local Python virtual environment in `./.venv/`.
    - Clone the latest `yt-dlp` source into `./vendor/`.
    - Download appropriate `ffmpeg` and `ffprobe` binaries.
    - `pip` install required packages (`playwright`, `curl_cffi`, etc.) into the virtual environment.
    - Install necessary browser binaries for Playwright.
	- Prompt to system install `jq` if not found.

## Usage

```bash
./bin/yt-menu
```

**Note:** You do **not** need to activate the virtual environment manually. The binary wrapper automatically routes execution through the isolated environment.

## Structure

```text
├── .venv/                       # Local Python virtual environment (Git-ignored)
├── bin/                         # User-facing executable wrapper
├── config/                      # User-specific configuration (Git-ignored)
├── data/                        # Static assets and templates
├── ffmpeg_gpl_materials/        # FFMpeg Compliance materials generated at installtime (Git-ignored)
├── lib/                         # Shared library scripts (env, config logic)
├── libexec/                     # Main worker scripts (llm-package, yt-album, etc.)
├── prompts/                     # User-definable llm-package dynamic prompt definitions
├── vendor/                      # Self-contained binaries (yt-dlp, ffmpeg)
├── COPYING                      # License
├── install.sh                   # Setup script
├── README.md                    # This readme
└── .gitignore                   # .gitignore
```

## Feedback

Feedback and contributions are welcome.

## License

GNU GPLv3+
