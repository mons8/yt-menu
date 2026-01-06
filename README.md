# yt-menu
**Audio Archival** and **context packages** for LLM.

`yt-menu` is a power-user TUI built on top of `yt-dlp` with a lot of glue inbetween. It bridges the gap between streaming content such as video and local archival (of audio music). Additionally, it features a powerful methodology for facilitating AI-assisted analysis.

While it excels at extracting highest-quality audio albums and discographies, its standout feature is the **llm-package** generator, a tool that converts video content (and its comments) into structured, token-conscious JSON datasets for feeding context to Large Language Models (ChatGPT, Gemini, Claude, Local LLaMA, etc.).

It manages its own copies of `yt-dlp` and `FFmpeg` and handles Python dependencies in an isolated `venv` without polluting your global system.

-----------------------------------
<img width="898" height="233" alt="Main Menu" src="https://github.com/user-attachments/assets/1170bea7-3e5a-4f0c-964a-f118003b09b3" />

_Main menu_

<img width="898" height="347" alt="Dynamic Prompt Configuration" src="https://github.com/user-attachments/assets/2b39cab1-e4a0-4780-a9e0-f07bf98d787f" />

_Prompt injection configuration_

## Core Capabilities


### 1. `llm-package`, AI-Context Pipeline 
_(Option 7. -> Enter URL and **append +** to access the Prompt Menu)_

Turn a streaming video into a "knowledge packet" for AI analysis.
*   **Prompt Injection:** A convenient TUI menu allows you to inject modular instructions directly into the payload. Select from categories like **TASK** ("Summarize", "Answer the Clickbait!"), **FORMAT** ("Markdown Spreadsheet"), or **TONE**. It also features a **CUSTOM** interactive mode for ad-hoc prompting. Your choices are then injected directly into the final JSON payload. 
	*   *Fully Extensible:* The menu is built dynamically from the `prompts/` directory. You can add or edit categories and prompts by creating folders and files.
*   **Rich Payload:** In addition to prompts and metadata, the JSON package contains:
    *   **Transcription:** Auto-selects the best available subtitle (prioritizing human-written and native language) and processes it for readability.
    *   **Comments:** Restructures flat YouTube comment dumps into human-readable conversation threads for sentiment analysis or public reception context.
*   **Token Conscious:** The output is a single, minimized `.json` file ready to be pasted into a chat window or used for RAG (Retrieval-Augmented Generation).
*   **Clipboard Ready:** The final package path (or content) is automatically copied to your clipboard for immediate use.

### Audio Archival
Robust and convenient tools for hoarders and archivists.
*   **Album & Channel Scraping:** Automates the downloading of entire albums or discographies via Channel `/releases` dynamic scraping.
*   **Metadata Tagging:** automatically applies sensible ID3 tags and filenaming conventions.
*   **Split Workflows:** Dedicated modes for Single Songs, Full Albums, or entire Channel Discographies.
*   **Download Directories:** Set your own preferred download folders.

## Key Features

-   **Self-Contained Ecosystem:**
    -   **Isolated Python:** Uses a local `.venv` to manage dependencies (`playwright`, `requests`) without touching your system Python.
    -   **Vendor Management:** Downloads its own local binaries for `yt-dlp` and `ffmpeg` (compliant builds) and other dependencies on install.
-   **Menu-Driven TUI:** Streamlined, low-click interactive interface.
-   **Smart Subtitles:** Intelligent logic to determine the "correct" language file to download based on video metadata.
-   **Subtitle Processing:** Processes subtitles into readable and token sensitive transcriptions.
-   **Comment Threading:** Custom Python logic converts flat YouTube comment JSON dumps into human-readable conversation threads.


## Requirements

-   A `bash` shell
-   `git`
-   `python3` (with `venv` module available)
-   `curl` or `wget`
-   `tar`
-   `jq` (required for `llm-package` JSON processing)

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

## Usage

```bash
./bin/yt-menu
```

**Note:** You do **not** need to activate the virtual environment manually. The binary wrapper automatically routes execution through the isolated environment.

## Project Structure

```text
├── .venv/       # Local Python virtual environment (Git-ignored)
├── bin/         # User-facing executable wrapper
├── config/      # User-specific configuration (Git-ignored)
├── data/        # Static assets and templates
├── lib/         # Shared library scripts (env, config logic)
├── libexec/     # The heavy-lifting worker scripts (llm-package, yt-album, etc.)
├── prompts/     # Dynamic prompt definitions for llm-package
├── vendor/      # Self-contained binaries (yt-dlp, ffmpeg)
└── install.sh   # Setup script
```

## Feedback

Feedback and contributions are welcome.

## License

GNU GPLv3+
