# yt-menu: Shell-Based Media Downloader

`yt-menu` is a convenient and menu-driven feature-rich suite of expanded functionality built upon `yt-dlp`. 

**Main functionalities**
- video-to-audio extraction with sensible ID3 and naming conventions:
    - albums
    - songs
    - entire channels (for albums)
- `llm-package` outputs an elaborate, token concious .json package of metadata and custom prompts
- metadata
    - transcription
    - description
    - comments (original output or readably processed & minimized)

It manages its own up-to-date copies of `yt-dlp` and `FFmpeg` and handles Python dependencies in `venv` without polluting the user's global system.


-----------------------------------
<img width="898" height="233" alt="20251111_132323" src="https://github.com/user-attachments/assets/1170bea7-3e5a-4f0c-964a-f118003b09b3" />

_Main menu_

<img width="898" height="347" alt="20251111_132417" src="https://github.com/user-attachments/assets/2b39cab1-e4a0-4780-a9e0-f07bf98d787f" />

_Optional prompt insertion_

## Features

- **Menu-Driven Interface:** Simple, numbered menu for common download tasks.
- **Specialized Downloaders:** Dedicated scripts for handling albums, multiple albums from a channel, single songs, and video comments.
- **Automated Channel Crawling:** Scans a channel's `/releases` or `/playlists` page to find and download all available albums.
- **Self-Contained Dependencies:** Manages its own local copies of `yt-dlp` and `FFmpeg` in a `vendor/` directory.
- **Isolated Python Environment:** Uses a local Python virtual environment (`.venv/`) to manage dependencies like `playwright` without affecting your system's Python.
- **Automatic `yt-dlp` Updates:** Checks for and pulls the latest version of `yt-dlp` on every launch.

## Requirements

- A `bash` shell.
- `git`
- `python3` (with `venv` module available)
- `curl` or `wget`
- `tar`

## Installation

The installation process is automated.

1.  **Clone repository and run install script**
    ```bash
    git clone https://github.com/mons8/yt-menu.git
    cd yt-menu
    chmod +x install.sh
    ./install.sh
    ```
    instrall.sh script will:
    - Check for required dependencies like `git` and `python3`.
    - Create a local Python virtual environment in `./.venv/`.
    - Git clone the latest `yt-dlp` into `./vendor/yt-dlp/`.
    - Download latest `yt-dlp`-specific build of `ffmpeg` and `ffprobe` binaries into the vendor directory while remaining compliant with ffmpeg licencing requirements.
    - `Pip`-install the required Python packages (`requests`, `playwright`, `curl_cffi`, etc) into virtual environment.
    - Install necessary browser binaries.
    - Prompt for system installation of `jq` and `deno`.

## Usage

```bash
./bin/yt-menu
```

You do **not** need to activate the virtual environment manually. The scripts are designed to be self-sufficient and will automatically use the correct Python interpreter and dependencies.



## Project Structure
```
-   `/.venv/`: The local Python virtual environment. (Git-ignored)
-   `/bin/`: The main, user-facing executable (`yt-menu`).
-   `/config/`: User-specific configuration files. (Git-ignored)
-   `/data/`: Static, version-controlled data, like the default config template.
-   `/lib/`: Core library scripts (`environment.sh`, `config_manager.sh`) that provide shared logic. Not meant to be executed directly.
-   `/libexec/`: The "worker" scripts that perform the actual download tasks, called by the main menu.
-   `/tmp/`: For temporary, transient files like generated URL lists. (Git-ignored)
-   `/vendor/`: Self-contained, third-party dependencies (`yt-dlp`, `ffmpeg`). (Git-ignored)
-   `install.sh`: The setup script.
```
## Feedback

Thanks for using and feedback is very welcome.

## License

GNU GPLv3+
