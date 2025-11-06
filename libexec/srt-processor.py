import json
import re
import sys
import os

def parse_time(time_str):
    """Converts SRT time format HH:MM:SS,ms to seconds."""
    parts = re.split(r'[:,]', time_str)
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2]) + int(parts[3]) / 1000

def format_time(seconds):
    """Converts seconds back to a consistent HH:MM:SS.ms format."""
    s = int(seconds)
    ms = int((seconds - s) * 1000)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

def process_srt_to_structured_array(srt_content):
    """
    Parses SRT content, intelligently combines text chunks into semantic
    sentences/paragraphs, and returns a list of hyper-efficient arrays.
    """
    srt_block_pattern = re.compile(
        r'(\d+)\s*([\d:,]+)\s*-->\s*([\d:,]+)\s*(.*?)\s*(?=\n\n|\Z)',
        re.DOTALL
    )
    
    blocks = srt_block_pattern.findall(srt_content)
    if not blocks:
        return []

    semantic_chunks = []
    current_chunk_text = ""
    chunk_start_time = None
    last_end_time = 0
    PAUSE_THRESHOLD_SECONDS = 0.8 # Slightly increased for better sentence grouping

    for i, block in enumerate(blocks):
        _num, start_time_str, end_time_str, text = block
        
        start_time_sec = parse_time(start_time_str.strip())
        end_time_sec = parse_time(end_time_str.strip())
        clean_text = text.strip().replace('\n', ' ')

        if not current_chunk_text:
            current_chunk_text = clean_text
            chunk_start_time = start_time_sec
        else:
            current_chunk_text += " " + clean_text

        # --- NEW, MORE ROBUST HEURISTIC ---
        # A chunk should end if:
        # 1. The current text block ends with sentence-ending punctuation.
        # 2. There is a significant pause BEFORE the next text block.
        # 3. It is the very last block of the transcription.
        
        is_sentence_end = clean_text.endswith(('.', '?', '!'))
        pause_duration = start_time_sec - last_end_time if i > 0 else 0
        
        finalize_chunk = (
            is_sentence_end or
            pause_duration > PAUSE_THRESHOLD_SECONDS or
            i == len(blocks) - 1
        )
        
        if finalize_chunk and current_chunk_text:
            semantic_chunks.append([
                format_time(chunk_start_time),
                format_time(end_time_sec),
                current_chunk_text.strip()
            ])
            # Reset for the next chunk
            current_chunk_text = ""
            chunk_start_time = None

        last_end_time = end_time_sec
        
    return semantic_chunks

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <path_to_srt_file>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    if not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

    with open(input_path, 'r', encoding='utf-8') as f:
        content = f.read()

    structured_data = process_srt_to_structured_array(content)
    
    base, _ = os.path.splitext(input_path)
    output_path = f"{base}.transcription_structured.json"
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(structured_data, f, ensure_ascii=False) # No indent for max efficiency
    
    print(output_path)