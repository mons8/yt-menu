# yt-menu: A Shell-Based Media Downloader

`yt-menu` is a self-contained menu-driven command-line interface for `yt-dlp`. It is designed for a consistent and convenient workflow for accessing yt-dlp and downloading video-to-audio as albums or songs and leveraging yt-dlp in other convenient ways.

It manages its own up-to-date copies of `yt-dlp` and `FFmpeg` and handles its own Python dependencies without polluting the user's global system.

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

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/mons8/yt-menu.git
    cd yt-menu
    ```

2.  **Run the installation script:**
    ```bash
    ./install.sh
    ```
    This script will:
    - Check for required dependencies like `git` and `python3`.
    - Create a local Python virtual environment in `./.venv/`.
    - Clone the latest `yt-dlp` into `./vendor/yt-dlp/`.
    - Download the latest `yt-dlp`-compatible `ffmpeg` and `ffprobe` binaries into the vendor directory.
    - `Pip`-install the required Python packages (`requests`, `playwright`, `curl_cffi`) into virtual environment.
    - Install Playwright's necessary browser binaries.

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

Thanks for using and feedback is welcome.

## License

GNU GPLv3+
