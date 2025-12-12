#!/usr/bin/env python3
"""
Generate compose.yaml from template and mode-specific overrides.

This script merges compose.yaml.template with either compose.core.yaml or
compose.enterprise.yaml to produce the final compose.yaml file.

Usage:
    # In core repository:
    cd /path/to/cosmos
    ./scripts/release/generate_compose.py --mode core

    # In enterprise repository:
    cd /path/to/cosmos-enterprise
    ../cosmos/scripts/release/generate_compose.py --mode enterprise --template ../cosmos/compose.yaml.template
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, Any

try:
    import yaml
except ImportError:
    print(
        "Error: PyYAML is required. Install it with: pip install --user pyyaml",
        file=sys.stderr,
    )
    sys.exit(1)


def load_yaml_file(filepath: Path) -> Dict[str, Any]:
    """Load a YAML file and return its contents as a dictionary."""
    try:
        return yaml.safe_load(filepath.read_text())
    except FileNotFoundError:
        print(f"Error: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file {filepath}: {e}", file=sys.stderr)
        sys.exit(1)


def load_template(filepath: Path) -> str:
    """Load the template file as plain text."""
    try:
        return filepath.read_text()
    except FileNotFoundError:
        print(f"Error: Template file not found: {filepath}", file=sys.stderr)
        sys.exit(1)


def replace_placeholders(template: str, overrides: Dict[str, Any]) -> str:
    """Replace all {{PLACEHOLDER}} markers in template with override values."""
    # Track which placeholders were found and replaced
    placeholders_in_template = set(re.findall(r"\{\{(\w+)\}\}", template))
    placeholders_replaced = set()

    # Filter out the mode key and create replacement mapping
    replacements = {
        key: "" if value is None else str(value)
        for key, value in overrides.items()
        if key != "mode"
    }

    # Perform replacements
    result = template
    for key, value in replacements.items():
        placeholder = f"{{{{{key}}}}}"
        if placeholder in result:
            result = result.replace(placeholder, value)
            placeholders_replaced.add(key)

    # Note: We don't remove blank lines here. The template should be designed
    # so that placeholders that can be empty are either inline or include
    # appropriate spacing in their replacement values.

    # Warn about unreplaced placeholders
    if unreplaced := placeholders_in_template - placeholders_replaced:
        available_keys = sorted(k for k in overrides.keys() if k != "mode")
        print(
            f"Warning: The following placeholders were not replaced: {', '.join(sorted(unreplaced))}",
            file=sys.stderr,
        )
        print(
            f"Available override keys: {', '.join(available_keys)}",
            file=sys.stderr,
        )

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Generate compose.yaml from template and mode-specific overrides"
    )
    parser.add_argument(
        "--mode",
        choices=["core", "enterprise"],
        required=True,
        help="Generation mode (core or enterprise)",
    )
    parser.add_argument(
        "--template",
        default=None,
        help="Path to compose.yaml.template (default: ./compose.yaml.template)",
    )
    parser.add_argument(
        "--overrides",
        default=None,
        help="Path to overrides file (default: ./compose.{mode}.yaml)",
    )
    parser.add_argument(
        "--output",
        default="compose.yaml",
        help="Output file path (default: ./compose.yaml)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print output to stdout instead of writing to file",
    )

    args = parser.parse_args()

    # Determine file paths
    current_dir = Path.cwd()

    if args.template:
        template_path = Path(args.template)
    else:
        template_path = current_dir / "compose.yaml.template"

    if args.overrides:
        overrides_path = Path(args.overrides)
    else:
        overrides_path = current_dir / f"compose.{args.mode}.yaml"

    output_path = Path(args.output)

    # Validate files exist
    if not template_path.exists():
        print(f"Error: Template file not found: {template_path}", file=sys.stderr)
        print(f"Current directory: {current_dir}", file=sys.stderr)
        sys.exit(1)

    if not overrides_path.exists():
        print(f"Error: Overrides file not found: {overrides_path}", file=sys.stderr)
        print(f"Current directory: {current_dir}", file=sys.stderr)
        sys.exit(1)

    # Load files
    print(f"Loading template from: {template_path}")
    template_content = load_template(template_path)

    print(f"Loading {args.mode} overrides from: {overrides_path}")
    overrides = load_yaml_file(overrides_path)

    # Verify mode matches
    if overrides.get("mode") != args.mode:
        print(
            f"Warning: Mode mismatch. Override file specifies '{overrides.get('mode')}' "
            f"but --mode is '{args.mode}'",
            file=sys.stderr,
        )

    # Generate compose.yaml
    print(f"Generating compose.yaml for {args.mode} mode...")
    output_content = replace_placeholders(template_content, overrides)

    # Output result
    if args.dry_run:
        print("\n" + "=" * 80)
        print("DRY RUN OUTPUT:")
        print("=" * 80 + "\n")
        print(output_content)
    else:
        with open(output_path, "w") as f:
            f.write(output_content)
        print(f"✓ Successfully generated: {output_path}")
        print(f"  Template: {template_path}")
        print(f"  Overrides: {overrides_path}")
        print(f"  Mode: {args.mode}")


if __name__ == "__main__":
    main()
