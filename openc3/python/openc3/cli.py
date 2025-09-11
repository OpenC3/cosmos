#!/usr/bin/env python3

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

import os
import sys
import argparse
from typing import List, Optional


def main(args: Optional[List[str]] = None) -> None:
    """Main entry point for the OpenC3 Python CLI"""
    
    # Check if OPENC3_NO_STORE is set - this prevents Redis connection attempts
    # Something with the module loading order, the os.environ['OPENC3_NO_STORE'] refused to set it correctly
    if not os.environ.get('OPENC3_NO_STORE'):
        print("Error: OPENC3_NO_STORE environment variable must be set to use the CLI.")
        print("Please run: export OPENC3_NO_STORE=1")
        print("Then run the CLI command again.")
        sys.exit(1)
    
    parser = argparse.ArgumentParser(
        prog='openc3pycli',
        description='OpenC3 Python Command Line Interface'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='openc3pycli 6.7.1-beta0'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    bridge_parser = subparsers.add_parser('bridge', help='Bridge related commands')
    bridge_parser.add_argument('filename', nargs='?', default='bridge.txt', help='Bridge configuration file')
    bridge_parser.add_argument('variables', nargs='*', help='Variables in key=value format')
    parsed_args = parser.parse_args(args)
    
    if parsed_args.command is None:
        parser.print_help()
        return
    
    # Handle commands
    if parsed_args.command == 'bridge':
        handle_bridge_command(parsed_args)

def run_bridge(filename, params):
    from openc3.bridge.bridge import Bridge
    
    variables = {}
    for param in params:
        name, value = param.split('=')
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
    

if __name__ == '__main__':
    main()