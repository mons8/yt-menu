#!/usr/bin/env python3
import argparse
import re
import os
import sys
import asyncio
import random
import string
import requests
import functools
from urllib.parse import urljoin, urlparse, urlunparse
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

# --- Helper Functions ---

def sanitize_filename(name: str) -> str:
    """Sanitizes a string to be a valid Windows filename."""
    name = re.sub(r'[\\/*?:"<>|]', "", name)
    name = name[:200].strip(" .")
    return name if name else "untitled_playlist_data"

def generate_random_string(length: int = 3) -> str:
    """Generates a random string of uppercase letters and digits."""
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=length))

async def timed_input(prompt: str, timeout: int) -> str:
    """
    Asks for user input with a timeout. Defaults to 'n'.
    Works within an asyncio event loop.
    """
    def get_input():
        try:
            return input()
        except EOFError:
            return 'n' # Default if input stream is closed

    print(prompt, file=sys.stderr, end='', flush=True)
    loop = asyncio.get_running_loop()
    try:
        # Run the blocking input() in a separate thread to not block the event loop
        result = await asyncio.wait_for(
            loop.run_in_executor(None, get_input),
            timeout=timeout
        )
        return result.strip() if result else 'y' # Default to 'y' if user just presses Enter
    except asyncio.TimeoutError:
        print("\nTimeout expired. Defaulting to 'No'.", file=sys.stderr)
        return 'n'

def suggest_alternative_url(url: str) -> str | None:
    """Suggests swapping /releases for /playlists or vice-versa."""
    parsed_url = urlparse(url)
    path = parsed_url.path.rstrip('/')
    
    if path.endswith('/releases'):
        new_path = path[:-len('releases')] + 'playlists'
        return urlunparse(parsed_url._replace(path=new_path))
    if path.endswith('/playlists'):
        new_path = path[:-len('playlists')] + 'releases'
        return urlunparse(parsed_url._replace(path=new_path))
    
    return None

# --- Scraper Implementations ---

async def run_playwright_scraper(url: str) -> tuple[str | None, list[str] | None]:
    """
    Launches a headless browser using Playwright to fetch page content,
    waits for dynamic content to load, and extracts playlist links and page title.
    """
    print(f"Debug (Playwright): Navigating to URL: {url}", file=sys.stderr)
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                locale='en-GB',
                timezone_id='Europe/London',
            )
            page = await context.new_page()

            # Go to the page and wait for network activity to cease. More reliable than wait_until='domcontentloaded' hopefully
            await page.goto(url, wait_until='networkidle', timeout=60000)

            try:
                # Attempt to click "Accept all" consent button
                await page.get_by_role("button", name="Accept all").first.click(timeout=5000)
                # Wait for the subsequent navigation/reload to finish
                await page.wait_for_load_state('networkidle', timeout=15000)
                print("Debug (Playwright): Consent form submitted.", file=sys.stderr)
            except PlaywrightTimeoutError:
                print("Debug (Playwright): No consent dialog found or it timed out.", file=sys.stderr)

            print("Debug (Playwright): Waiting for playlist grid renderer to load...", file=sys.stderr)
            # Wait for the main container of the playlists, which is more stable.
            await page.wait_for_selector('ytd-rich-grid-renderer', timeout=30000)
            print("Debug (Playwright): Playlist grid renderer loaded.", file=sys.stderr)

            links_with_list_param = await page.locator('a[href*="list="]').all()
            playlist_ids = set()
            for link in links_with_list_param:
                href = await link.get_attribute('href')
                if href:
                    match = re.search(r'list=([a-zA-Z0-9_-]+)', href)
                    if match:
                        playlist_ids.add(match.group(1))

            playlist_urls = sorted([f"https://www.youtube.com/playlist?list={pid}" for pid in playlist_ids])
            page_title = await page.title()
            await browser.close()
            return page_title, playlist_urls

    except PlaywrightTimeoutError as e:
        print(f"Error (Playwright): Timed out waiting for content on '{url}'. Details: {e}", file=sys.stderr)
        return "playlist_data", [] # Return empty list on timeout, allowing fallback
    except Exception as e:
        print(f"Error (Playwright): An unexpected error occurred: {e}", file=sys.stderr)
        return None, None # Return None on critical failure

def run_requests_scraper(url: str) -> tuple[str | None, list[str] | None]:
    """
    Fetches HTML using Requests, attempts to bypass consent screens, and extracts playlist links.
    NOTE: This is a synchronous function.
    """
    print(f"Debug (Requests): Attempting to fetch URL: {url}", file=sys.stderr)
    try:
        session = requests.Session()
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
            'Cookie': 'CONSENT=YES+cb.20240520-07-p0.en+FX+000; SOCS=CAESEwgDEgk0ODE3Nzk3MjAaAmVuIAEaBgiA_LmvBg'
        })
        response = session.get(url, timeout=20)
        response.raise_for_status()
        html_content = response.text

        # This simple regex is often sufficient for static pages but may miss dynamic content.
        title_match = re.search(r"<title>(.*?)</title>", html_content, re.IGNORECASE | re.DOTALL)
        page_title = title_match.group(1).strip() if title_match else "playlist_data"

        playlist_references = set(re.findall(r'["\'](/playlist\?list=([a-zA-Z0-9_-]+))["\']', html_content))
        playlist_urls = sorted([f"https://www.youtube.com{match[0]}" for match in playlist_references])

        return page_title, playlist_urls

    except requests.exceptions.RequestException as e:
        print(f"Error (Requests): Request failed for URL '{url}': {e}", file=sys.stderr)
        return None, None
    except Exception as e:
        print(f"Error (Requests): An unexpected error occurred: {e}", file=sys.stderr)
        return None, None

# --- Main Logic ---

async def get_playlists_from_url(url: str) -> tuple[str | None, list[str] | None]:
    """Orchestrates the scraping process with primary and backup methods."""

    # --- Attempt 1: Requests (Lightweight & Primary) ---
    print("\n--- Attempt 1: Using Requests (lightweight) ---", file=sys.stderr)
    loop = asyncio.get_running_loop()
    # Run the synchronous 'requests' function in a thread to avoid blocking asyncio
    requests_result = await loop.run_in_executor(
        None, functools.partial(run_requests_scraper, url=url)
    )

    page_title = "playlist_data" # Default title
    if requests_result:
        page_title_req, playlist_urls_req = requests_result
        if page_title_req: page_title = page_title_req

        if playlist_urls_req: # Success with Requests
            print(f"Success (Requests): Found {len(playlist_urls_req)} playlists.", file=sys.stderr)
            return page_title, playlist_urls_req

    # --- Attempt 2: Playwright (Heavyweight Fallback) ---
    print("\n--- Requests failed or found no playlists. Attempt 2: Using Playwright (heavyweight fallback) ---", file=sys.stderr)

    playwright_result = await run_playwright_scraper(url)

    if playwright_result:
        page_title_pw, playlist_urls_pw = playwright_result
        if page_title_pw: page_title = page_title_pw

        if playlist_urls_pw: # Success with Playwright
            print(f"Success (Playwright): Found {len(playlist_urls_pw)} playlists.", file=sys.stderr)
            return page_title, playlist_urls_pw

    print("--- Both scraping methods failed or found no playlists. ---", file=sys.stderr)
    return page_title, [] # Return original title and empty list if both failed

async def main():
    parser = argparse.ArgumentParser(
        description="Unified Playlist Retriever: Fetches a URL using Playwright, falls back to Requests, extracts YouTube playlist links, saves them, and prints the file path to STDOUT.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--url", required=True, help="Full URL of the YouTube page (e.g., channel/releases) to scan.")
    parser.add_argument("--output-dir", required=True, help="Absolute path to the directory where the temporary URL list file should be saved.")
    args = parser.parse_args()


    current_url = args.url
    page_title, playlist_urls = await get_playlists_from_url(current_url)

    # --- Attempt 3: Suggest alternative URL if still no results ---
    if not playlist_urls:
        alternative_url = suggest_alternative_url(current_url)
        if alternative_url:
            prompt = f"\nNo playlists found. Try alternative URL '{alternative_url}'? [Y/n] (5s timeout): "
            choice = await timed_input(prompt, 5)
            if choice.lower() == 'y':
                print(f"--- User accepted. Retrying with {alternative_url} ---", file=sys.stderr)
                current_url = alternative_url
                page_title, playlist_urls = await get_playlists_from_url(current_url)

    # --- Save results to file ---
    if page_title is None:
        print(f"Error: All attempts to fetch or process '{args.url}' failed catastrophically. Exiting.", file=sys.stderr)
        sys.exit(1)

    # script_dir = os.path.dirname(os.path.abspath(__file__))
    # output_dir = os.path.join(script_dir, "playlist-retreiver_URLs")
    # os.makedirs(args.output_dir, exist_ok=True)
    #
    # sanitized_page_title = sanitize_filename(page_title)
    # random_suffix = generate_random_string(3)
    # output_filename = f"{sanitized_page_title}_{random_suffix}.txt"
    # output_filepath = os.path.join(output_dir, output_filename)
    if not os.path.isdir(args.output_dir):
        print(f"Error: Provided output directory does not exist: {args.output_dir}", file=sys.stderr)
        sys.exit(1)

    sanitized_page_title = sanitize_filename(page_title)
    random_suffix = generate_random_string(3)
    output_filename = f"{sanitized_page_title}_{random_suffix}.txt"
    output_filepath = os.path.join(args.output_dir, output_filename)

    try:
        with open(output_filepath, "w", encoding="utf-8") as f:
            if playlist_urls:
                f.write("\n".join(playlist_urls) + "\n")
                print(f"\nDebug: Success. Found {len(playlist_urls)} unique playlist URLs.", file=sys.stderr)
            else:
                f.write(f"No playlist URLs found on {current_url}.\n")
                print(f"\nDebug: Failure. No playlist URLs found on {current_url} after all attempts.", file=sys.stderr)
        print(f"Debug: Results saved to: {output_filepath}", file=sys.stderr)
    except IOError as e:
        print(f"Error: Could not write to file '{output_filepath}': {e}", file=sys.stderr)
        sys.exit(1)

    # CRITICAL: Print the full path to standard output for other scripts
    print(output_filepath)

if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
