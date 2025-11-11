import json
import re
import sys
import os
from datetime import timedelta

def parse_ass_time(time_str):
    """Converts ASS time format H:MM:SS.cs to seconds."""
    h, m, s, cs = map(int, re.split(r'[:.]', time_str))
    return timedelta(hours=h, minutes=m, seconds=s, milliseconds=cs * 10).total_seconds()

def format_time(seconds):
    """Converts seconds back to a consistent HH:MM:SS.ms format."""
    s = int(seconds)
    ms = int((seconds - s) * 1000)
    m, s = divmod(s, 60)
    h, m = divmod(m, 60)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

def process_ass_to_structured_array(ass_content):
    """
    Parses ASS content, extracts dialogue lines, cleans them of styling codes,
    and returns a list of hyper-efficient [startTime, endTime, text] arrays.
    """
    if '[Events]' not in ass_content:
        return []

    events_section = ass_content.split('[Events]')[1]
    lines = events_section.strip().split('\n')
    
    # The 'Format' line defines the column order. We must parse it to be robust.
    format_line = next((line for line in lines if line.startswith('Format:')), None)
    if not format_line:
        return []
    
    columns = [col.strip() for col in format_line.split(':', 1)[1].split(',')]
    try:
        start_idx = columns.index('Start')
        end_idx = columns.index('End')
        text_idx = columns.index('Text')
    except ValueError:
        # If the essential columns aren't present, we cannot proceed.
        print("Error: 'Start', 'End', or 'Text' not found in ASS Format line.", file=sys.stderr)
        return []
        
    dialogue_lines = []
    for line in lines:
        if line.startswith('Dialogue:'):
            parts = line.split(':', 1)[1].split(',', text_idx)
            text = parts[text_idx]
            
            # Clean text of ASS styling overrides (e.g., {\i1}, {\c&HFFFFFF&})
            clean_text = re.sub(r'\{.*?\}', '', text).strip()
            
            if clean_text:
                start_time_sec = parse_ass_time(parts[start_idx].strip())
                end_time_sec = parse_ass_time(parts[end_idx].strip())
                
                dialogue_lines.append([
                    format_time(start_time_sec),
                    format_time(end_time_sec),
                    clean_text
                ])
                
    return dialogue_lines

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <path_to_ass_file>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    if not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

    with open(input_path, 'r', encoding='utf-8') as f:
        content = f.read()

    structured_data = process_ass_to_structured_array(content)
    
    base, _ = os.path.splitext(input_path)
    output_path = f"{base}.transcription_structured.json"
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(structured_data, f, ensure_ascii=False) # No indent
    
    print(output_path)