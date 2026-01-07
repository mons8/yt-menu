# yt-menu
**Audio Archival** and **context packages** for LLM.

`yt-menu` is a power-user TUI built on top of `yt-dlp`. It aims to minimize clicks between streaming content such as video, and its local archival as audio music. 

Additionally, it features a powerful methodology for facilitating AI-assisted analysis.

While it excels at extracting highest-quality audio albums and discographies, its standout feature is the **llm-package** generator, a tool that converts video content (and its comments) into structured, token-conscious JSON datasets for feeding context to Large Language Models (ChatGPT, Gemini, Claude, Local LLaMA, etc.).

It manages its own copies of `yt-dlp` and `FFmpeg` and handles Python dependencies in an isolated `venv` without polluting your global system.

-----------------------------------
<img width="809" height="339" alt="20260106_230800" src="https://github.com/user-attachments/assets/bab97c26-2ebb-4cfe-b97c-694be26ade94" />

_Main menu_

<img width="809" height="493" alt="prompt-injection" src="https://github.com/user-attachments/assets/c1a86478-85b4-4e1e-b413-4f6881429478" />

_Prompt Injection_

## Core Capabilities


### `llm-package`, AI-Context Pipeline 
_(Option 7. -> Enter URL and **append <kbd>+</kbd>** (e.g. `https://domain.com/video-url+`) to access the menu._

Turn a streaming video, its comments and metadata, into a `knowledge packet` for AI analysis.

*   **Token Conscious:** The output is a single, minimized `.json` file ready to be pasted into a chat window or used for RAG (Retrieval-Augmented Generation).
*   **Clipboard:** The final package path (or content) is automatically copied to your clipboard for immediate use.
*   **Prompt Injection:** A convenient TUI menu allows you to inject modular instructions directly into the payload. Select from categories like **TASK** ("Summarize", "Answer the Clickbait!"), **FORMAT** ("Markdown Spreadsheet"), or **TONE**. It also features a **CUSTOM** interactive mode for ad-hoc prompting. Your choices are then injected directly into the final JSON payload. 
	*   *Fully Extensible:* The menu is built dynamically from the `prompts/` directory. You can add or edit categories and prompts by creating folders and files.
*   **Rich Payload:** In addition to `prompts` and `metadata`, the JSON package contains:
    *   **`Transcription:`** Auto-selects the best available subtitle (prioritizing human-written and native language) and processes it for readability. **Processes** subtitles into readable and token sensitive transcriptions.
    *   **`Comments:`** Restructures flat YouTube comment dumps into human-and-AI-readable conversation threads for analysis and public reception context. This process prunes out _a lot_ of unnedeed and detrimental tokens from the API output.

### Audio Archival
Robust and convenient tools for hoarders and archivists.
*   **Album & Channel Scraping:** Automates the downloading of entire albums or discographies via Channel `/releases` dynamic scraping.
*   **Metadata Tagging:** Automatically applies sensible ID3 tags and filenaming conventions.
*   **Split Workflows:** Dedicated modes for Single Songs, Full Albums, or entire Channel Discographies.
*   **Download Directories:** Customize download folders per mode.

## Key Features

-   **Audio Archival** and **context packages** for LLM.
-   **Menu-Driven TUI:** Streamlined, low-click interactive interface.
-   **Self-Contained Ecosystem:**
    -   **Isolated Python:** Uses a local `.venv` to manage dependencies (`playwright`, `requests`) without touching your system Python.
    -   **Vendor Management:** Downloads its own local binaries for `yt-dlp` and `ffmpeg` (compliant builds) and other dependencies on install.

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
	- Prompt to system install `jq` if not found.

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
