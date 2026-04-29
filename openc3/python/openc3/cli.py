#!/usr/bin/env python3

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# To use the openc3pycli, first run
#       python3 -m pip install -e .
# to download all the dependencies defined in the pyproject.toml file.
# A venv may be required to be activated prior to running the pip install. If so, run the following:
#       python3 -m venv /path/to/your/venv
#       source /path/to/your/venv/bin/activate
#       python3 -m pip install -e .

"""
OpenC3 Python CLI - Command line interface for OpenC3 Python tools
"""

import argparse
import os


# OPENC3_NO_STORE tells the Logger to skip publishing log messages to a Redis
# store that doesn't exist when running the CLI on a host (e.g. a bridge).
# It must be set before any openc3 module is imported, because
# openc3/environment.py reads it once at import time and freezes it as a
# module-level constant. All openc3 imports below are deferred into the
# command handlers so this assignment lands first. setdefault preserves any
# value the user already exported.
os.environ.setdefault("OPENC3_NO_STORE", "1")


def main(args: list[str] | None = None) -> None:
    """Main entry point for the OpenC3 Python CLI"""

    parser = argparse.ArgumentParser(prog="openc3pycli", description="OpenC3 Python Command Line Interface")

    parser.add_argument("--version", action="version", version="openc3pycli 6.7.1-beta0")

    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    bridge_parser = subparsers.add_parser("bridge", help="Run a COSMOS bridge from a bridge configuration file")
    bridge_parser.add_argument("filename", nargs="?", default="bridge.txt", help="Bridge configuration file")
    bridge_parser.add_argument("variables", nargs="*", help="Variables in key=value format")
    bridgesetup_parser = subparsers.add_parser("bridgesetup", help="Generate a default bridge configuration file")
    bridgesetup_parser.add_argument("filename", nargs="?", default="bridge.txt", help="Output filename")
    parsed_args = parser.parse_args(args)

    if parsed_args.command is None:
        parser.print_help()
        return

    # Handle commands
    if parsed_args.command == "bridge":
        handle_bridge_command(parsed_args)
    elif parsed_args.command == "bridgesetup":
        handle_bridgesetup_command(parsed_args)


def run_bridge(filename, params):
    from openc3.bridge.bridge import Bridge

    variables = {}
    for param in params:
        name, value = param.split("=")
        if name and value:
            variables[name] = value
        else:
            raise SyntaxError(f"Invalid variable passed to bridge (syntax name=value): {param}")

    bridge = Bridge(filename, variables)
    bridge.wait_forever()


def handle_bridge_command(args) -> None:
    filename = args.filename
    variables = args.variables or []
    run_bridge(filename, variables)


def handle_bridgesetup_command(args) -> None:
    from openc3.bridge.bridge_config import BridgeConfig

    filename = args.filename
    if not os.path.exists(filename):
        BridgeConfig.generate_default(filename)


if __name__ == "__main__":
    main()
