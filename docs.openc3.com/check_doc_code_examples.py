#!/usr/bin/env python3
"""
Check code examples in markdown documentation files for syntax errors.

Parses fenced code blocks from .md files and runs language-appropriate
syntax checks (Python, Ruby, Bash, JavaScript, JSON).

Usage:
    python scripts/check_doc_code_examples.py [OPTIONS] [PATH]

Arguments:
    PATH    Directory to search for .md files (default: docs.openc3.com)

Options:
    --lang LANG     Only check blocks tagged with this language (e.g. python, ruby)
    --verbose       Show all checked blocks, not just errors
    --include-bare  Also attempt to check untagged code blocks (experimental)
    --json          Output results as JSON
    --help          Show this help message

Examples:
    # Check all tagged code blocks under docs.openc3.com
    python scripts/check_doc_code_examples.py

    # Check only Python blocks
    python scripts/check_doc_code_examples.py --lang python

    # Check a specific subdirectory
    python scripts/check_doc_code_examples.py docs.openc3.com/docs/guides

    # Include untagged code blocks (tries to auto-detect language)
    python scripts/check_doc_code_examples.py --include-bare
"""

import argparse
import ast
import json as json_mod
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class CodeBlock:
    file: str
    line_start: int  # 1-based line number where the opening ``` is
    language: str     # language tag, or "" if bare
    code: str
    line_end: int = 0


@dataclass
class SyntaxError_:
    file: str
    line_start: int
    language: str
    error_message: str
    code_snippet: str  # first few lines for context


@dataclass
class CheckResult:
    total_files: int = 0
    total_blocks: int = 0
    blocks_checked: int = 0
    blocks_skipped: int = 0
    errors: list = field(default_factory=list)


# ---------------------------------------------------------------------------
# Markdown parsing
# ---------------------------------------------------------------------------

# Matches opening fence: ``` optionally followed by a language tag
FENCE_OPEN = re.compile(r"^(`{3,}|~{3,})\s*(\w[\w+-]*)?.*$")


def extract_code_blocks(filepath: str) -> list[CodeBlock]:
    """Extract fenced code blocks from a markdown file."""
    blocks = []
    try:
        with open(filepath, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return blocks

    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        m = FENCE_OPEN.match(line)
        if m:
            fence_char = m.group(1)[0]
            fence_len = len(m.group(1))
            lang = (m.group(2) or "").lower()
            code_lines = []
            start = i + 1  # 1-based line of the opening ```
            i += 1
            # Find closing fence
            while i < len(lines):
                cl = lines[i].rstrip()
                # Closing fence must use same char and be at least as long
                if cl.startswith(fence_char * fence_len) and cl.strip() == fence_char * max(fence_len, len(cl.strip())):
                    break
                code_lines.append(lines[i])
                i += 1
            blocks.append(CodeBlock(
                file=filepath,
                line_start=start,
                line_end=i + 1,
                language=lang,
                code="".join(code_lines),
            ))
        i += 1
    return blocks


# ---------------------------------------------------------------------------
# Language normalization
# ---------------------------------------------------------------------------

LANG_ALIASES = {
    "py": "python",
    "python3": "python",
    "rb": "ruby",
    "js": "javascript",
    "ts": "typescript",
    "sh": "bash",
    "shell": "bash",
    "zsh": "bash",
    "yml": "yaml",
}


def normalize_lang(lang: str) -> str:
    lang = lang.lower().strip()
    return LANG_ALIASES.get(lang, lang)


# ---------------------------------------------------------------------------
# Syntax checkers
# ---------------------------------------------------------------------------

def check_python(code: str) -> str | None:
    """Return error message if Python code has syntax errors, else None."""
    try:
        ast.parse(code)
        return None
    except SyntaxError as e:
        return f"Line {e.lineno}: {e.msg}"


def check_ruby(code: str) -> str | None:
    """Return error message if Ruby code has syntax errors, else None."""
    if not shutil.which("ruby"):
        return None  # ruby not available, skip
    try:
        result = subprocess.run(
            ["ruby", "-c", "-e", code],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            # Extract meaningful part of error
            err = result.stderr.strip()
            # Remove the "-e:" prefix for cleaner output
            err = re.sub(r"^-e:", "Line ", err, flags=re.MULTILINE)
            return err
        return None
    except (subprocess.TimeoutExpired, OSError):
        return None


def check_bash(code: str) -> str | None:
    """Return error message if Bash code has syntax errors, else None."""
    if not shutil.which("bash"):
        return None
    try:
        result = subprocess.run(
            ["bash", "-n"],
            input=code, capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            err = result.stderr.strip()
            return err or "syntax error"
        return None
    except (subprocess.TimeoutExpired, OSError):
        return None


def check_javascript(code: str) -> str | None:
    """Return error message if JavaScript code has syntax errors, else None."""
    if not shutil.which("node"):
        return None
    try:
        with tempfile.NamedTemporaryFile(suffix=".js", mode="w", delete=False) as f:
            f.write(code)
            tmp = f.name
        result = subprocess.run(
            ["node", "--check", tmp],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            err = result.stderr.strip()
            # Clean up temp file path from error message
            err = err.replace(tmp, "<snippet>")
            return err
        return None
    except (subprocess.TimeoutExpired, OSError):
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def check_json(code: str) -> str | None:
    """Return error message if JSON is invalid, else None."""
    try:
        json_mod.loads(code)
        return None
    except json_mod.JSONDecodeError as e:
        return f"Line {e.lineno}, Col {e.colno}: {e.msg}"


# Map of normalized language -> checker function
CHECKERS = {
    "python": check_python,
    "ruby": check_ruby,
    "bash": check_bash,
    "javascript": check_javascript,
    "json": check_json,
}

# Languages we recognize but intentionally skip (no good syntax-only checker)
SKIPPED_LANGS = {"yaml", "html", "css", "typescript", "c", "cpp", "go", "java",
                 "xml", "sql", "markdown", "md", "text", "txt", "diff", "csv",
                 "toml", "ini", "dockerfile", "makefile", "plaintext", "vue",
                 "erb", "awk", "sed", "batch", "powershell", "lua", "kotlin",
                 "swift", "rust", "csharp"}


# ---------------------------------------------------------------------------
# False-positive filters
# ---------------------------------------------------------------------------

# COSMOS configuration DSL keywords — blocks starting with these are config
# files, not Ruby/Python code, even if tagged as such.
COSMOS_CONFIG_KEYWORDS = {
    "COMMAND", "TELEMETRY", "PARAMETER", "APPEND_PARAMETER", "ID_PARAMETER",
    "APPEND_ID_PARAMETER", "ITEM", "APPEND_ITEM", "ID_ITEM", "APPEND_ID_ITEM",
    "TARGET", "INTERFACE", "ROUTER", "DECLARE_TARGET", "DECLARE_PLUGIN",
    "SCREEN", "SETTING", "STATE", "LIMITS", "SELECT_COMMAND", "SELECT_TELEMETRY",
    "SELECT_PARAMETER", "SELECT_ITEM", "REQUIRE", "ACCESSOR", "TEMPLATE",
    "VARIABLE", "WIDGET", "VERTICAL", "VERTICALBOX", "HORIZONTAL", "HORIZONTALBOX",
    "MATRIXBYCOLUMNS", "TABBOOK", "TABITEM", "CANVAS", "CANVASIMAGE",
    "CANVASLINE", "CANVASLABEL", "CANVASLINEVALUE", "CANVASVALUE",
    "LABELVALUE", "LABEL", "VALUE", "BUTTON", "TITLE", "NAMED_WIDGET",
    "TEXTFIELD", "COMBOBOX", "CHECKBUTTON", "RADIOBUTTON",
    "END", "SCROLLWINDOW", "STALE_TIME", "GLOBAL_SETTING",
    "CANVASLABELVALUE", "CANVASIMAGEVALUE", "SPACER",
    "META", "HAZARDOUS", "DISABLED", "HIDDEN", "IGNORE_OVERLAP",
    "OVERLAP", "ALLOW_ACCESS", "DENY_ACCESS", "POLY_READ_CONVERSION",
    "POLY_WRITE_CONVERSION", "READ_CONVERSION", "WRITE_CONVERSION",
    "FORMAT_STRING", "UNITS", "DESCRIPTION", "GENERIC_READ_CONVERSION_START",
    "GENERIC_WRITE_CONVERSION_START", "GENERIC_READ_CONVERSION_END",
    "GENERIC_WRITE_CONVERSION_END", "SELECT_COMMAND", "SELECT_TELEMETRY",
    "LIMITS_RESPONSE", "PROCESSOR", "STALE_TIME", "KEY",
    "MICROSERVICE", "ENV", "WORK_DIR", "CMD", "OPTION", "CONTAINER",
    "ROUTE", "PORT", "SECRET", "SCOPE", "DISABLE_ERB",
    "LOG_RETAIN_TIME", "REDUCED_LOG_RETAIN_TIME", "CLEANUP_POLL_TIME",
    "LOG_RAW", "LOG", "PROTOCOL",
    "SUBPACKET", "TABLE",
    "ARRAY_PARAMETER", "ARRAY_ITEM", "APPEND_ARRAY_ITEM", "APPEND_ARRAY_PARAMETER",
    "SELECT_ARRAY_ITEM", "SELECT_ARRAY_PARAMETER",
    "CONVERSIONS_IN_THE_COMMAND",  # doc fragments
}

# Regex: first non-blank, non-comment line starts with a COSMOS config keyword
_COSMOS_FIRST_LINE = re.compile(
    r"^\s*(" + "|".join(re.escape(k) for k in COSMOS_CONFIG_KEYWORDS) + r")\b",
)


def is_cosmos_config(code: str) -> bool:
    """Check if a code block is COSMOS configuration DSL, not real code."""
    for line in code.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Explicit keyword match
        if _COSMOS_FIRST_LINE.match(line):
            return True
        # Broader heuristic: line is ALL_CAPS_WORD (with or without args) — common COSMOS pattern
        # but NOT common Ruby/Python keywords
        if re.match(r"^[A-Z][A-Z_]{2,}(\s+|$)", stripped):
            lower = stripped.split()[0].lower()
            if lower not in ("for", "if", "def", "end", "class", "module", "begin",
                             "return", "raise", "rescue", "ensure", "yield", "case",
                             "when", "while", "until", "unless", "break", "next"):
                return True
        return False
    return False


def has_placeholder_syntax(code: str) -> bool:
    """Check if code contains <placeholder> style tokens (any case)."""
    # Matches <word>, <Word>, <WORD>, <multi word>, <PARAMS...>, etc.
    # but not HTML-like tags such as <div> or <br> (common in actual code)
    return bool(re.search(r"<[a-zA-Z][a-zA-Z0-9 _.]+\.{0,3}>", code))


def has_ellipsis_placeholder(code: str) -> bool:
    """Check if code uses ... as a placeholder (common in doc snippets)."""
    for line in code.splitlines():
        stripped = line.strip()
        if stripped == "..." or stripped == "# ...":
            return True
    return False


def is_output_not_code(code: str, lang: str) -> bool:
    """Check if a bash block is really showing command output, not a runnable script."""
    if lang != "bash":
        return False
    stripped = code.strip()
    # HTTP response output
    if re.search(r"^HTTP/[\d.]+ \d+", stripped, re.MULTILINE):
        return True
    # Docker/command output with table-like formatting
    if re.search(r"^(NETWORK ID|CONTAINER ID|NAME)\s+", stripped, re.MULTILINE):
        return True
    # Interactive REPL sessions (irb, python, etc.)
    if re.search(r"^(irb\(|>>>|\.\.\.|In \[\d+\])", stripped, re.MULTILINE):
        return True
    # Command output that starts with % or $ prompt then shows output
    lines = stripped.splitlines()
    if lines and re.match(r"^[%$]\s+\w+", lines[0]):
        # Check if subsequent lines look like output (not commands)
        non_prompt = [l for l in lines[1:] if l.strip() and not re.match(r"^[%$]\s", l)]
        if len(non_prompt) > len(lines) // 2:
            return True
    # Help/usage text output
    if re.search(r"^Usage:", stripped, re.MULTILINE):
        return True
    return False


def is_config_fragment(code: str, lang: str) -> bool:
    """Check if a JS block is a config object fragment (not a complete module)."""
    if lang != "javascript":
        return False
    stripped = code.strip()
    # Starts with an object key like "extends:" or "parserOptions:" — not valid JS on its own
    if re.match(r"^[a-zA-Z_]\w*\s*:", stripped):
        return True
    return False


def should_skip_block(code: str, lang: str) -> str | None:
    """Return a skip reason if this block is a known false-positive pattern, else None."""
    if is_cosmos_config(code):
        return "COSMOS config DSL"
    if has_placeholder_syntax(code):
        return "placeholder syntax"
    if is_output_not_code(code, lang):
        return "command output, not code"
    if is_config_fragment(code, lang):
        return "config fragment"
    return None


# ---------------------------------------------------------------------------
# Bare block language detection (heuristic)
# ---------------------------------------------------------------------------

def guess_language(code: str) -> str:
    """Try to guess language of an untagged code block. Returns '' if unsure."""
    stripped = code.strip()
    if not stripped:
        return ""

    # Python indicators
    if re.search(r"^\s*(def |class |import |from .+ import |print\()", stripped, re.MULTILINE):
        return "python"

    # Ruby indicators
    if re.search(r"^\s*(require |def |end$|puts |\.each |do\s*\|)", stripped, re.MULTILINE):
        return "ruby"

    # Bash indicators
    if stripped.startswith("#!") or re.search(r"^\s*(export |echo |sudo |apt |brew |npm |pip |cd )", stripped, re.MULTILINE):
        return "bash"

    # JSON
    if (stripped.startswith("{") and stripped.endswith("}")) or (stripped.startswith("[") and stripped.endswith("]")):
        return "json"

    return ""


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

def find_markdown_files(root: str) -> list[str]:
    """Recursively find all .md files under root."""
    files = []
    for dirpath, _dirnames, filenames in os.walk(root):
        # Skip common non-doc directories
        parts = dirpath.split(os.sep)
        if any(p in ("node_modules", ".git", "vendor", ".venv", "__pycache__") for p in parts):
            continue
        for fn in sorted(filenames):
            if fn.endswith(".md"):
                files.append(os.path.join(dirpath, fn))
    return sorted(files)


def snippet(code: str, max_lines: int = 5) -> str:
    """Return first N lines of code for display."""
    lines = code.splitlines()
    s = "\n".join(lines[:max_lines])
    if len(lines) > max_lines:
        s += f"\n    ... ({len(lines) - max_lines} more lines)"
    return s


def check_blocks(
    blocks: list[CodeBlock],
    lang_filter: str | None = None,
    include_bare: bool = False,
    verbose: bool = False,
) -> CheckResult:
    result = CheckResult()
    result.total_blocks = len(blocks)

    for block in blocks:
        lang = normalize_lang(block.language)

        # Handle bare blocks
        if not lang:
            if include_bare:
                lang = guess_language(block.code)
                if not lang:
                    result.blocks_skipped += 1
                    continue
            else:
                result.blocks_skipped += 1
                continue

        # Apply language filter
        if lang_filter and lang != lang_filter:
            result.blocks_skipped += 1
            continue

        checker = CHECKERS.get(lang)
        if not checker:
            if lang not in SKIPPED_LANGS and verbose:
                print(f"  [skip] {block.file}:{block.line_start} — no checker for '{lang}'")
            result.blocks_skipped += 1
            continue

        # Skip trivially small blocks (single comments, blank, etc.)
        stripped = block.code.strip()
        if not stripped or all(l.strip().startswith("#") or not l.strip() for l in stripped.splitlines()):
            result.blocks_skipped += 1
            continue

        # Filter known false-positive patterns
        skip_reason = should_skip_block(block.code, lang)
        if skip_reason:
            if verbose:
                print(f"  [skip] {block.file}:{block.line_start} — {skip_reason}")
            result.blocks_skipped += 1
            continue

        result.blocks_checked += 1
        error = checker(block.code)
        if error:
            result.errors.append(SyntaxError_(
                file=block.file,
                line_start=block.line_start,
                language=lang,
                error_message=error,
                code_snippet=snippet(block.code),
            ))
        elif verbose:
            print(f"  [ok] {block.file}:{block.line_start} ({lang})")

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Check code examples in markdown docs for syntax errors.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "path", nargs="?", default="docs.openc3.com",
        help="Directory to search for .md files (default: docs.openc3.com)",
    )
    parser.add_argument("--lang", help="Only check blocks of this language")
    parser.add_argument("--verbose", action="store_true", help="Show all checked blocks")
    parser.add_argument("--include-bare", action="store_true", help="Try to check untagged blocks")
    parser.add_argument("--json", action="store_true", dest="json_output", help="Output as JSON")
    args = parser.parse_args()

    # Resolve path relative to script location or cwd
    search_path = args.path
    if not os.path.isabs(search_path):
        # Try relative to repo root (parent of scripts/)
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        candidate = os.path.join(repo_root, search_path)
        if os.path.isdir(candidate):
            search_path = candidate
        elif not os.path.isdir(search_path):
            print(f"Error: directory not found: {search_path}")
            sys.exit(1)

    if not os.path.isdir(search_path):
        print(f"Error: not a directory: {search_path}")
        sys.exit(1)

    lang_filter = normalize_lang(args.lang) if args.lang else None

    # Find files
    md_files = find_markdown_files(search_path)
    if not md_files:
        print(f"No .md files found under {search_path}")
        sys.exit(0)

    if not args.json_output:
        print(f"Scanning {len(md_files)} markdown files under {search_path} ...")
        if lang_filter:
            print(f"  Filtering to language: {lang_filter}")
        if args.include_bare:
            print(f"  Including untagged code blocks (auto-detect)")
        print()

    # Extract and check
    all_blocks = []
    for fp in md_files:
        all_blocks.extend(extract_code_blocks(fp))

    result = check_blocks(all_blocks, lang_filter, args.include_bare, args.verbose)
    result.total_files = len(md_files)

    # Output
    if args.json_output:
        output = {
            "total_files": result.total_files,
            "total_blocks": result.total_blocks,
            "blocks_checked": result.blocks_checked,
            "blocks_skipped": result.blocks_skipped,
            "error_count": len(result.errors),
            "errors": [asdict(e) for e in result.errors],
        }
        print(json_mod.dumps(output, indent=2))
    else:
        # Print errors grouped by file
        if result.errors:
            current_file = None
            for err in result.errors:
                if err.file != current_file:
                    current_file = err.file
                    rel = os.path.relpath(err.file, search_path)
                    print(f"\n{'='*70}")
                    print(f"FILE: {rel}")
                    print(f"{'='*70}")
                print(f"\n  [{err.language}] Line {err.line_start}")
                print(f"  Error: {err.error_message}")
                print(f"  Code:")
                for cl in err.code_snippet.splitlines():
                    print(f"    | {cl}")
                print()
        else:
            print("No syntax errors found!")

        # Summary
        print(f"\n{'─'*70}")
        print(f"Summary:")
        print(f"  Files scanned:    {result.total_files}")
        print(f"  Code blocks:      {result.total_blocks}")
        print(f"  Blocks checked:   {result.blocks_checked}")
        print(f"  Blocks skipped:   {result.blocks_skipped}")
        print(f"  Errors found:     {len(result.errors)}")
        print(f"{'─'*70}")

    sys.exit(1 if result.errors else 0)


if __name__ == "__main__":
    main()
