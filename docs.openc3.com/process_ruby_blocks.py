#!/usr/bin/env python3
"""
Script to process Ruby code blocks in markdown files.
Finds "Ruby Example:\n\n```ruby\n" blocks and replaces them with just the code content.
"""

import re
import sys

def process_file(filename):
    """Process a file to replace Ruby code blocks with just their content."""
    try:
        with open(filename, 'r', encoding='utf-8') as file:
            content = file.read()
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
        return False
    except Exception as e:
        print(f"Error reading file '{filename}': {e}")
        return False

    # Patterns to match Ruby and Python examples
    r_ex_pattern = r'Ruby Example:\n\n```(ruby|python)?\n(.*?)\n```'
    p_ex_pattern = r'Python Example:\n\n```(ruby|python)?\n(.*?)\n```'
    b_ex_pattern = r'Ruby / Python Example:\n\n```(ruby|python)?\n(.*?)\n```'
    b_syn_pattern = r'Ruby / Python Syntax:\n\n```(ruby|python)?\n(.*?)\n```'
    r_syn_pattern = r'Ruby Syntax:\n\n```(ruby|python)?\n(.*?)\n```'
    p_syn_pattern = r'Python Syntax:\n\n```(ruby|python)?\n(.*?)\n```'

    def ex_ruby_replacement(match):
        # Wrap the Ruby code content in TabItem tags
        return f'<Tabs groupId="script-language">\n<TabItem value="ruby" label="Ruby Example">\n\n```ruby\n{match.group(2)}\n```\n\n</TabItem>'

    def ex_python_replacement(match):
        # Wrap the Python code content in TabItem tags
        return f'<TabItem value="python" label="Python Example">\n\n```python\n{match.group(2)}\n```\n</TabItem>\n</Tabs>'

    def ex_both_replacement(match):
        # Wrap the Python code content in TabItem tags
        return f'<Tabs groupId="script-language">\n<TabItem value="ruby" label="Ruby Example">\n\n```ruby\n{match.group(2)}\n```\n\n</TabItem>\n\n<TabItem value="python" label="Python Example">\n\n```python\n{match.group(2)}\n```\n</TabItem>\n</Tabs>'

    def syn_ruby_replacement(match):
        # Wrap the Ruby code content in TabItem tags
        return f'<Tabs groupId="script-language">\n<TabItem value="ruby" label="Ruby Syntax">\n\n```ruby\n{match.group(2)}\n```\n\n</TabItem>'

    def syn_python_replacement(match):
        # Wrap the Python code content in TabItem tags
        return f'<TabItem value="python" label="Python Syntax">\n\n```python\n{match.group(2)}\n```\n</TabItem>\n</Tabs>'

    def syn_both_replacement(match):
        # Wrap the Python code content in TabItem tags
        return f'<Tabs groupId="script-language">\n<TabItem value="ruby" label="Ruby Syntax">\n\n```ruby\n{match.group(2)}\n```\n\n</TabItem>\n\n<TabItem value="python" label="Python Syntax">\n\n```python\n{match.group(2)}\n```\n</TabItem>\n</Tabs>'

    # Replace all matches with TabItem wrapped content
    new_content = re.sub(b_syn_pattern, syn_both_replacement, content, flags=re.DOTALL)
    new_content = re.sub(b_ex_pattern, ex_both_replacement, new_content, flags=re.DOTALL)
    new_content = re.sub(r_ex_pattern, ex_ruby_replacement, new_content, flags=re.DOTALL)
    new_content = re.sub(p_ex_pattern, ex_python_replacement, new_content, flags=re.DOTALL)
    new_content = re.sub(r_syn_pattern, syn_ruby_replacement, new_content, flags=re.DOTALL)
    new_content = re.sub(p_syn_pattern, syn_python_replacement, new_content, flags=re.DOTALL)

    # Check if any changes were made
    if content == new_content:
        print(f"No Ruby or Python code blocks found in '{filename}'")
        return True

    try:
        with open(filename, 'w', encoding='utf-8') as file:
            file.write(new_content)
        print(f"Successfully processed '{filename}'")
        return True
    except Exception as e:
        print(f"Error writing to file '{filename}': {e}")
        return False

def main():
    """Main function to handle command line arguments."""
    if len(sys.argv) != 2:
        print("Usage: python3 process_ruby_blocks.py <filename>")
        sys.exit(1)

    filename = sys.argv[1]
    success = process_file(filename)

    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()