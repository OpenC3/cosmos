#!/usr/bin/env python3
"""
Check code examples in markdown documentation files for syntax errors,
and optionally check external URLs for broken links (404s).

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
    --check-urls    Check external URLs for broken links (404s)
    --file FILE     Check only this specific .md file
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

    # Check external URLs for broken links
    python scripts/check_doc_code_examples.py --check-urls

    # Check URLs in a single file
    python scripts/check_doc_code_examples.py --check-urls --file docs.openc3.com/docs/guides/troubleshooting.md
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
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class CodeBlock:
    file: str
    line_start: int  # 1-based line number where the opening ``` is
    language: str  # language tag, or "" if bare
    code: str
    line_end: int = 0


@dataclass
class SyntaxError:
    file: str
    line_start: int
    language: str
    error_message: str
    code_snippet: str  # first few lines for context


@dataclass
class BrokenUrl:
    file: str
    line: int
    url: str
    status_code: int  # 0 for connection errors
    error_message: str


@dataclass
class CheckResult:
    total_files: int = 0
    total_blocks: int = 0
    blocks_checked: int = 0
    blocks_skipped: int = 0
    errors: list = field(default_factory=list)
    url_errors: list = field(default_factory=list)
    urls_checked: int = 0


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
                if cl.startswith(
                    fence_char * fence_len
                ) and cl.strip() == fence_char * max(fence_len, len(cl.strip())):
                    break
                code_lines.append(lines[i])
                i += 1
            blocks.append(
                CodeBlock(
                    file=filepath,
                    line_start=start,
                    line_end=i + 1,
                    language=lang,
                    code="".join(code_lines),
                )
            )
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
            capture_output=True,
            text=True,
            timeout=10,
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
            input=code,
            capture_output=True,
            text=True,
            timeout=10,
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
            capture_output=True,
            text=True,
            timeout=10,
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
SKIPPED_LANGS = {
    "yaml",
    "html",
    "css",
    "typescript",
    "c",
    "cpp",
    "go",
    "java",
    "xml",
    "sql",
    "markdown",
    "md",
    "text",
    "txt",
    "diff",
    "csv",
    "toml",
    "ini",
    "dockerfile",
    "makefile",
    "plaintext",
    "vue",
    "erb",
    "awk",
    "sed",
    "batch",
    "powershell",
    "lua",
    "kotlin",
    "swift",
    "rust",
    "csharp",
}


# ---------------------------------------------------------------------------
# False-positive filters
# ---------------------------------------------------------------------------

# COSMOS configuration DSL keywords — blocks starting with these are config
# files, not Ruby/Python code, even if tagged as such.
COSMOS_CONFIG_KEYWORDS = {
    "COMMAND",
    "TELEMETRY",
    "PARAMETER",
    "APPEND_PARAMETER",
    "ID_PARAMETER",
    "APPEND_ID_PARAMETER",
    "ITEM",
    "APPEND_ITEM",
    "ID_ITEM",
    "APPEND_ID_ITEM",
    "TARGET",
    "INTERFACE",
    "ROUTER",
    "DECLARE_TARGET",
    "DECLARE_PLUGIN",
    "SCREEN",
    "SETTING",
    "STATE",
    "LIMITS",
    "SELECT_COMMAND",
    "SELECT_TELEMETRY",
    "SELECT_PARAMETER",
    "SELECT_ITEM",
    "REQUIRE",
    "ACCESSOR",
    "TEMPLATE",
    "VARIABLE",
    "WIDGET",
    "VERTICAL",
    "VERTICALBOX",
    "HORIZONTAL",
    "HORIZONTALBOX",
    "MATRIXBYCOLUMNS",
    "TABBOOK",
    "TABITEM",
    "CANVAS",
    "CANVASIMAGE",
    "CANVASLINE",
    "CANVASLABEL",
    "CANVASLINEVALUE",
    "CANVASVALUE",
    "LABELVALUE",
    "LABEL",
    "VALUE",
    "BUTTON",
    "TITLE",
    "NAMED_WIDGET",
    "TEXTFIELD",
    "COMBOBOX",
    "CHECKBUTTON",
    "RADIOBUTTON",
    "END",
    "SCROLLWINDOW",
    "STALE_TIME",
    "GLOBAL_SETTING",
    "CANVASLABELVALUE",
    "CANVASIMAGEVALUE",
    "SPACER",
    "META",
    "HAZARDOUS",
    "DISABLED",
    "HIDDEN",
    "IGNORE_OVERLAP",
    "OVERLAP",
    "ALLOW_ACCESS",
    "DENY_ACCESS",
    "POLY_READ_CONVERSION",
    "POLY_WRITE_CONVERSION",
    "READ_CONVERSION",
    "WRITE_CONVERSION",
    "FORMAT_STRING",
    "UNITS",
    "DESCRIPTION",
    "GENERIC_READ_CONVERSION_START",
    "GENERIC_WRITE_CONVERSION_START",
    "GENERIC_READ_CONVERSION_END",
    "GENERIC_WRITE_CONVERSION_END",
    "SELECT_COMMAND",
    "SELECT_TELEMETRY",
    "LIMITS_RESPONSE",
    "PROCESSOR",
    "STALE_TIME",
    "KEY",
    "MICROSERVICE",
    "ENV",
    "WORK_DIR",
    "CMD",
    "OPTION",
    "CONTAINER",
    "ROUTE",
    "PORT",
    "SECRET",
    "SCOPE",
    "DISABLE_ERB",
    "LOG_RETAIN_TIME",
    "REDUCED_LOG_RETAIN_TIME",
    "CLEANUP_POLL_TIME",
    "LOG_RAW",
    "LOG",
    "PROTOCOL",
    "SUBPACKET",
    "TABLE",
    "ARRAY_PARAMETER",
    "ARRAY_ITEM",
    "APPEND_ARRAY_ITEM",
    "APPEND_ARRAY_PARAMETER",
    "SELECT_ARRAY_ITEM",
    "SELECT_ARRAY_PARAMETER",
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
            if lower not in (
                "for",
                "if",
                "def",
                "end",
                "class",
                "module",
                "begin",
                "return",
                "raise",
                "rescue",
                "ensure",
                "yield",
                "case",
                "when",
                "while",
                "until",
                "unless",
                "break",
                "next",
            ):
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
        non_prompt = [line for line in lines[1:] if line.strip() and not re.match(r"^[%$]\s", line)]
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
    if re.search(
        r"^\s*(def |class |import |from .+ import |print\()", stripped, re.MULTILINE
    ):
        return "python"

    # Ruby indicators
    if re.search(
        r"^\s*(require |def |end$|puts |\.each |do\s*\|)", stripped, re.MULTILINE
    ):
        return "ruby"

    # Bash indicators
    if stripped.startswith("#!") or re.search(
        r"^\s*(export |echo |sudo |apt |brew |npm |pip |cd )", stripped, re.MULTILINE
    ):
        return "bash"

    # JSON
    if (stripped.startswith("{") and stripped.endswith("}")) or (
        stripped.startswith("[") and stripped.endswith("]")
    ):
        return "json"

    return ""


# ---------------------------------------------------------------------------
# URL extraction and checking
# ---------------------------------------------------------------------------

# Matches markdown links [text](url) and bare URLs starting with http(s)
URL_MARKDOWN_LINK = re.compile(r"\[([^\]]*)\]\((https?://[^\s)]+)\)")
URL_BARE = re.compile(r"(?<!\()(https?://[^\s)\]>\"'`,]+)")

# Domains to skip — localhost, example domains, placeholders
SKIP_URL_DOMAINS = {
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "example.com",
    "example.org",
    "example.net",
    "your-bucket",
    "mycompany.com",
}

# URL substrings known to be valid but that block automated requests (403/404).
# Any URL containing one of these substrings is skipped.
WHITELISTED_URLS = [
    "raspberrypi.com/software",
    "npmjs.com/package",
    "github.com/OpenC3/cosmos/assets",
    "www.computerhope.com",
    "mydomain.com",
]

# Domains that receive a GitHub auth token
GITHUB_DOMAINS = {"github.com", "raw.githubusercontent.com", "api.github.com"}


def _get_github_token() -> str | None:
    """Get a GitHub token from GITHUB_TOKEN env var or `gh auth token`."""
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    if shutil.which("gh"):
        try:
            result = subprocess.run(
                ["gh", "auth", "token"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except (subprocess.TimeoutExpired, OSError):
            pass
    return None


def _is_github_url(url: str) -> bool:
    """Check if a URL is a GitHub domain that should receive auth.
    Excludes release download URLs which use redirect-based auth."""
    try:
        domain = url.split("//", 1)[1].split("/", 1)[0].split(":")[0]
    except IndexError:
        return False
    if domain not in GITHUB_DOMAINS:
        return False
    # Release asset downloads redirect to S3 and reject token auth
    if "/releases/download/" in url:
        return False
    return True


# Matches github.com/:owner/:repo/blob/:ref/:path or /tree/:ref/:path
_GITHUB_BLOB_TREE = re.compile(
    r"^https://github\.com/([^/]+)/([^/]+)/(blob|tree)/([^/]+)/(.+)$"
)
# Matches github.com/:owner/:repo/releases/tag/:tag
_GITHUB_RELEASE_TAG = re.compile(
    r"^https://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)$"
)
# Matches github.com/:owner/:repo (with optional trailing slash, .git, or ?query)
_GITHUB_REPO = re.compile(
    r"^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?(?:\?.*)?$"
)


def _github_api_url(url: str) -> str | None:
    """Convert a github.com web URL to an API URL for auth-friendly checking.
    Returns None if the URL doesn't match a convertible pattern."""
    m = _GITHUB_BLOB_TREE.match(url)
    if m:
        owner, repo, _, ref, path = m.groups()
        return f"https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={ref}"
    m = _GITHUB_RELEASE_TAG.match(url)
    if m:
        owner, repo, tag = m.groups()
        return f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    m = _GITHUB_REPO.match(url)
    if m:
        owner, repo = m.groups()
        return f"https://api.github.com/repos/{owner}/{repo}"
    return None


def extract_urls(filepath: str) -> list[tuple[int, str]]:
    """Extract external URLs from a markdown file. Returns list of (line_number, url)."""
    urls = []
    try:
        with open(filepath, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return urls

    in_code_block = False
    for i, line in enumerate(lines, 1):
        stripped = line.rstrip()
        # Track code fences to skip URLs inside code blocks
        if FENCE_OPEN.match(stripped):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue

        # Extract from markdown links [text](url)
        for m in URL_MARKDOWN_LINK.finditer(line):
            urls.append((i, m.group(2)))
        # Extract bare URLs not already captured by markdown links
        link_spans = [(m.start(2), m.end(2)) for m in URL_MARKDOWN_LINK.finditer(line)]
        for m in URL_BARE.finditer(line):
            # Skip if this URL is part of a markdown link already found
            if any(s <= m.start() < e for s, e in link_spans):
                continue
            urls.append((i, m.group(0)))

    return urls


def should_skip_url(url: str) -> bool:
    """Check if a URL should be skipped (localhost, example domains, whitelisted, etc)."""
    if any(pattern in url for pattern in WHITELISTED_URLS):
        return True
    try:
        # Extract domain from URL
        domain = url.split("//", 1)[1].split("/", 1)[0].split(":")[0]
    except IndexError:
        return True
    if domain in SKIP_URL_DOMAINS:
        return True
    # Skip URLs with obvious placeholders
    if "<" in url or "{" in url or "HOSTNAME" in url or "PASSWORD" in url:
        return True
    # Skip URLs with HTML entities (e.g. http://&lt;Your...)
    if "&lt;" in url or "&gt;" in url:
        return True
    # Skip URLs with a port number (e.g. http://host:2900) — local/test URLs
    host_port = url.split("//", 1)[1].split("/", 1)[0]
    if re.match(r"^.+:\d+$", host_port):
        return True
    return False


def check_url(url: str, timeout: int = 15, github_token: str | None = None) -> (
    tuple[int, str]
):
    """Check if a URL is reachable. Returns (status_code, error_message).
    status_code 0 means connection error. Empty error_message means success."""
    # Strip trailing punctuation that may have been captured
    url = url.rstrip(".,;:!?")
    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; OpenC3-DocChecker/1.0)",
    }
    check_url_actual = url
    if github_token and _is_github_url(url):
        headers["Authorization"] = f"token {github_token}"
        # GitHub web pages return 404 for private repos even with a token.
        # Convert to an API URL that properly respects token auth.
        api_url = _github_api_url(url)
        if api_url:
            check_url_actual = api_url
            headers["Accept"] = "application/vnd.github.v3+json"
    req = urllib.request.Request(check_url_actual, method="HEAD", headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
        return (resp.status, "")
    except urllib.error.HTTPError as e:
        if e.code == 405:
            # HEAD not allowed, retry with GET
            req = urllib.request.Request(
                check_url_actual, method="GET", headers=headers
            )
            try:
                resp = urllib.request.urlopen(req, timeout=timeout)
                return (resp.status, "")
            except urllib.error.HTTPError as e2:
                return (e2.code, str(e2.reason))
            except Exception as e2:
                return (0, str(e2))
        return (e.code, str(e.reason))
    except urllib.error.URLError as e:
        return (0, str(e.reason))
    except Exception as e:
        return (0, str(e))


def check_urls_in_files(
    md_files: list[str],
    verbose: bool = False,
    max_workers: int = 10,
) -> tuple[int, list[BrokenUrl]]:
    """Check all external URLs across markdown files. Returns (urls_checked, broken_urls)."""
    # Resolve GitHub token once for all URL checks
    github_token = _get_github_token()
    if github_token and verbose:
        print("  Using GitHub authentication for github.com URLs")

    # Collect all unique URLs with their locations
    url_locations: dict[str, list[tuple[str, int]]] = {}  # url -> [(file, line), ...]
    for fp in md_files:
        for line_num, url in extract_urls(fp):
            if should_skip_url(url):
                continue
            clean_url = url.rstrip(".,;:!?")
            url_locations.setdefault(clean_url, []).append((fp, line_num))

    unique_urls = list(url_locations.keys())
    if not unique_urls:
        return (0, [])

    broken = []
    checked = 0

    def _check_one(url):
        return url, check_url(url, github_token=github_token)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(_check_one, url): url for url in unique_urls}
        for future in as_completed(futures):
            url, (status, error_msg) = future.result()
            checked += 1
            is_error = status == 0 or status >= 400
            if is_error:
                for filepath, line_num in url_locations[url]:
                    broken.append(
                        BrokenUrl(
                            file=filepath,
                            line=line_num,
                            url=url,
                            status_code=status,
                            error_message=error_msg or f"HTTP {status}",
                        )
                    )
            if verbose:
                if is_error:
                    print(f"  [BROKEN] {url} — {error_msg or f'HTTP {status}'}")
                else:
                    print(f"  [ok] {url}")

    # Sort broken URLs by file then line
    broken.sort(key=lambda b: (b.file, b.line))
    return (checked, broken)


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

def find_markdown_files(root: str) -> list[str]:
    """Recursively find all .md files under root."""
    files = []
    for dirpath, _dirnames, filenames in os.walk(root):
        # Skip common non-doc directories
        parts = dirpath.split(os.sep)
        if any(
            p in ("node_modules", ".git", "vendor", ".venv", "__pycache__")
            for p in parts
        ):
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
                print(
                    f"  [skip] {block.file}:{block.line_start} — no checker for '{lang}'"
                )
            result.blocks_skipped += 1
            continue

        # Skip trivially small blocks (single comments, blank, etc.)
        stripped = block.code.strip()
        if not stripped or all(
            line.strip().startswith("#") or not line.strip() for line in stripped.splitlines()
        ):
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
            result.errors.append(
                SyntaxError(
                    file=block.file,
                    line_start=block.line_start,
                    language=lang,
                    error_message=error,
                    code_snippet=snippet(block.code),
                )
            )
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
        "path",
        nargs="?",
        default="docs.openc3.com",
        help="Directory to search for .md files (default: docs.openc3.com)",
    )
    parser.add_argument("--lang", help="Only check blocks of this language")
    parser.add_argument(
        "--verbose", action="store_true", help="Show all checked blocks"
    )
    parser.add_argument(
        "--include-bare", action="store_true", help="Try to check untagged blocks"
    )
    parser.add_argument(
        "--json", action="store_true", dest="json_output", help="Output as JSON"
    )
    parser.add_argument(
        "--check-urls",
        action="store_true",
        help="Check external URLs for broken links (404s)",
    )
    parser.add_argument("--file", help="Check only this specific .md file")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Single-file mode
    if args.file:
        file_path = args.file
        if not os.path.isabs(file_path):
            candidate = os.path.join(repo_root, file_path)
            if os.path.isfile(candidate):
                file_path = candidate
        if not os.path.isfile(file_path):
            print(f"Error: file not found: {file_path}")
            sys.exit(1)
        md_files = [file_path]
        search_path = os.path.dirname(file_path)
    else:
        # Resolve path relative to script location or cwd
        search_path = args.path
        if not os.path.isabs(search_path):
            # Try relative to repo root (parent of scripts/)
            candidate = os.path.join(repo_root, search_path)
            if os.path.isdir(candidate):
                search_path = candidate
            elif not os.path.isdir(search_path):
                print(f"Error: directory not found: {search_path}")
                sys.exit(1)

        if not os.path.isdir(search_path):
            print(f"Error: not a directory: {search_path}")
            sys.exit(1)

        # Find files
        md_files = find_markdown_files(search_path)
        if not md_files:
            print(f"No .md files found under {search_path}")
            sys.exit(0)

    lang_filter = normalize_lang(args.lang) if args.lang else None

    if not args.json_output:
        if args.file:
            print(f"Checking {md_files[0]} ...")
        else:
            print(f"Scanning {len(md_files)} markdown files under {search_path} ...")
        if lang_filter:
            print(f"  Filtering to language: {lang_filter}")
        if args.include_bare:
            print("  Including untagged code blocks (auto-detect)")
        print()

    # Extract and check
    all_blocks = []
    for fp in md_files:
        all_blocks.extend(extract_code_blocks(fp))

    result = check_blocks(all_blocks, lang_filter, args.include_bare, args.verbose)
    result.total_files = len(md_files)

    # URL checking
    if args.check_urls:
        if not args.json_output:
            print("Checking external URLs for broken links ...")
            print()
        urls_checked, url_errors = check_urls_in_files(md_files, args.verbose)
        result.urls_checked = urls_checked
        result.url_errors = url_errors

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
        if args.check_urls:
            output["urls_checked"] = result.urls_checked
            output["broken_url_count"] = len(result.url_errors)
            output["broken_urls"] = [asdict(e) for e in result.url_errors]
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
                print("  Code:")
                for cl in err.code_snippet.splitlines():
                    print(f"    | {cl}")
                print()
        else:
            print("No syntax errors found!")

        # Print broken URLs
        if args.check_urls:
            print()
            if result.url_errors:
                current_file = None
                for err in result.url_errors:
                    if err.file != current_file:
                        current_file = err.file
                        rel = os.path.relpath(err.file, search_path)
                        print(f"\n{'='*70}")
                        print(f"BROKEN URLs in: {rel}")
                        print(f"{'='*70}")
                    status = (
                        f"HTTP {err.status_code}"
                        if err.status_code
                        else "Connection error"
                    )
                    print(f"\n  Line {err.line}: {err.url}")
                    print(f"  Status: {status} — {err.error_message}")
            else:
                print("No broken URLs found!")

        # Summary
        print(f"\n{'─'*70}")
        print("Summary:")
        print(f"  Files scanned:    {result.total_files}")
        print(f"  Code blocks:      {result.total_blocks}")
        print(f"  Blocks checked:   {result.blocks_checked}")
        print(f"  Blocks skipped:   {result.blocks_skipped}")
        print(f"  Syntax errors:    {len(result.errors)}")
        if args.check_urls:
            print(f"  URLs checked:     {result.urls_checked}")
            print(f"  Broken URLs:      {len(result.url_errors)}")
        print(f"{'─'*70}")

    has_errors = bool(result.errors) or bool(result.url_errors)
    sys.exit(1 if has_errors else 0)


if __name__ == "__main__":
    main()
