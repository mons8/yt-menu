import json
import sys
import os

def process_and_restructure_comments(input_file_path):
    """
    Reads a .info.json file, extracts and minimizes comment data, and
    restructures the flat list into a nested tree of conversations.
    """
    try:
        with open(input_file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading or parsing {input_file_path}: {e}", file=sys.stderr)
        return None

    if 'comments' not in data or not data['comments']:
        return []

    comment_map = {}
    processed_comments = []

    # --- First Pass: Minimize and Map ---
    # Create optimized comment objects and map them by their ID for fast lookup.
    for comment in data['comments']:
        opt_comment = {
            'id': comment.get('id'),
            'author': comment.get('author'),
            'text': comment.get('text'),
            'replies': []  # Initialize replies list for every comment
        }

        # Conditionally include non-default values
        if (like_count := comment.get('like_count', 0)) > 0:
            opt_comment['like_count'] = like_count
        if comment.get('author_is_uploader', False):
            opt_comment['author_is_uploader'] = True
        
        # Store the original parent ID for the linking pass
        parent_id = comment.get('parent')
        
        comment_map[opt_comment['id']] = opt_comment
        processed_comments.append((opt_comment, parent_id))

    # --- Second Pass: Link and Build Tree ---
    # Iterate through the processed comments to place them in the tree.
    root_comments = []
    for comment_obj, parent_id in processed_comments:
        if parent_id == 'root':
            root_comments.append(comment_obj)
        else:
            if parent_node := comment_map.get(parent_id):
                parent_node['replies'].append(comment_obj)
            else:
                # This comment is a reply to a deleted or unretrievable comment.
                # We'll treat it as a root comment to avoid losing it.
                comment_obj['is_orphan'] = True # Add context
                root_comments.append(comment_obj)

    return root_comments

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <path_to_info.json>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    
    if not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

    structured_data = process_and_restructure_comments(input_path)

    if structured_data is not None:
        base, _ = os.path.splitext(input_path)
        # Use a more descriptive intermediate filename
        output_path = f"{base}.comments_threaded.json"
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(structured_data, f, indent=2, ensure_ascii=False)
        
        print(f"Successfully created structured comment file at: {output_path}", file=sys.stderr)
        # Print ONLY the path to stdout for the calling script.
        print(output_path)