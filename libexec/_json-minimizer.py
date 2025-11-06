import json
import sys
import os

def maximize_comment_optimization(input_file_path):
    """
    Reads a .info.json file, extracts only essential data and non-zero/true
    values, and returns a maximally optimized list of comment dictionaries.
    """
    try:
        with open(input_file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading or parsing {input_file_path}: {e}", file=sys.stderr)
        return None

    if 'comments' not in data or not data['comments']:
        # If there are no comments, return an empty list. This is not an error.
        return []

    optimized_comments = []
    for comment in data['comments']:
        # Start with the absolute core data
        opt_comment = {
            'id': comment.get('id'),
            'parent': comment.get('parent'),
            'author': comment.get('author'),
            'text': comment.get('text')
        }

        # Conditionally include like_count only if it's greater than 0
        like_count = comment.get('like_count', 0)
        if like_count > 0:
            opt_comment['like_count'] = like_count

        # Conditionally include boolean flags only if they are true
        if comment.get('is_pinned', False):
            opt_comment['is_pinned'] = True
        
        if comment.get('author_is_uploader', False):
            opt_comment['author_is_uploader'] = True

        optimized_comments.append(opt_comment)
        
    return optimized_comments

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python json_comment_max_optimizer.py <path_to_info.json>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    
    if not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

    optimized_data = maximize_comment_optimization(input_path)

    if optimized_data is not None:
        base, ext = os.path.splitext(input_path)
        output_path = f"{base}.comments_max_optimized.json"
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(optimized_data, f, indent=2, ensure_ascii=False)
        
        # Announce success to the user on stderr.
        print(f"Successfully created optimized comment file at: {output_path}", file=sys.stderr)
        
        # Print ONLY the path to stdout for the calling script.
        print(output_path)