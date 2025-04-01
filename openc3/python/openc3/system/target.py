# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import glob
import pathlib
import os
from typing import Optional
from openc3.top_level import add_to_search_path
from openc3.utilities.logger import Logger
from openc3.config.config_parser import ConfigParser


class Target:
    """Target encapsulates the information about a OpenC3 target. Targets are
    accessed through interfaces and have command and telemetry definition files
    which define their access."""

    def __init__(self, target_name: str, path: os.PathLike[str], gem_path: Optional[str] = None):
        """Creates a new target by processing the target.txt file in the directory
        given by the path joined with the target_name. Records all the command
        and telemetry definition files found in the targets cmd_tlm directory.
        System uses this list and processes them using PacketConfig."""
        self.language = "python"
        self.ignored_parameters = []
        self.ignored_items = []
        self.cmd_tlm_files = []
        self.interface = None
        self.routers = []
        self.cmd_cnt = 0
        self.tlm_cnt = 0
        self.cmd_unique_id_mode = False
        self.tlm_unique_id_mode = False
        self.dir: Optional[str] = None
        self.id: Optional[str] = None
        self.filename: Optional[str] = None
        self.name = target_name.upper()

        self.get_target_dir(path, gem_path)
        self.process_target_config_file()

        # If target.txt didn't specify specific cmd/tlm files then add everything
        if len(self.cmd_tlm_files) == 0:
            self.add_all_cmd_tlm()
        else:
            self.add_cmd_tlm_partials()

    def process_file(self, filename: str):
        """Parses the target configuration file
        Args:
            filename (str) The target configuration file to parse
        """
        Logger.info(f"Processing python target definition in file '{filename}'")
        parser = ConfigParser("https://docs.openc3.com/docs/configuration/target")
        for keyword, parameters in parser.parse_file(filename):
            match keyword:
                case "LANGUAGE":
                    usage = f"{keyword} <ruby | python>"
                    parser.verify_num_parameters(1, 1, usage)
                    self.language = parameters[0].lower()

                case "REQUIRE":
                    # This keyword is deprecated in Python
                    pass

                case "IGNORE_PARAMETER" | "IGNORE_ITEM":
                    usage = f"{keyword} <{keyword.split('_')[1]} NAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    if "PARAMETER" in keyword:
                        self.ignored_parameters.append(parameters[0].upper())
                    if "ITEM" in keyword:
                        self.ignored_items.append(parameters[0].upper())

                case "COMMANDS" | "TELEMETRY":
                    usage = f"{keyword} <FILENAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    filename = pathlib.Path(self.dir, "cmd_tlm", parameters[0])
                    if not filename.exists():
                        raise parser.error(f"{filename} not found")
                    self.cmd_tlm_files.append(filename)

                case "CMD_UNIQUE_ID_MODE":
                    usage = keyword
                    parser.verify_num_parameters(0, 0, usage)
                    self.cmd_unique_id_mode = True

                case "TLM_UNIQUE_ID_MODE":
                    usage = keyword
                    parser.verify_num_parameters(0, 0, usage)
                    self.tlm_unique_id_mode = True

                case _:
                    # blank lines will have a None keyword and should not raise an exception
                    if keyword:
                        raise Exception(parser.error(f"Unknown keyword '{keyword}'"))

    def as_json(self):
        config = {
            "name": self.name,
            "ignored_parameters": self.ignored_parameters,
            "ignored_items": self.ignored_items,
            "cmd_tlm_files": self.cmd_tlm_files,
            "id": self.id,
        }
        if self.cmd_unique_id_mode:
            config["cmd_unique_id_mode"] = True
        if self.tlm_unique_id_mode:
            config["tlm_unique_id_mode"] = True
        return config

    def get_target_dir(self, path: os.PathLike[str], gem_path: Optional[str]):
        """Get the target directory and add the target's lib folder to the
        search path if it exists
        Args:
            path (os.PathLike[str]):
            gem_path (os.)
        """
        self.dir = gem_path if gem_path else os.path.join(path, self.name)
        lib_dir = os.path.join(self.dir, "lib")
        if os.path.exists(lib_dir):
            add_to_search_path(lib_dir, False)
        proc_dir = os.path.join(self.dir, "procedures")
        if os.path.exists(proc_dir):
            add_to_search_path(proc_dir, False)

    # Process the target's configuration file if it exists
    def process_target_config_file(self):
        self.filename = os.path.join(self.dir, "target.txt")
        if os.path.exists(self.filename):
            self.process_file(self.filename)
        else:
            self.filename = None

        id_filename = os.path.join(self.dir, "target_id.txt")
        if os.path.exists(id_filename):
            with open(id_filename) as f:
                self.id = f.read().strip()
        else:
            self.id = None

    # Automatically add all command and telemetry definitions to the list
    def add_all_cmd_tlm(self):
        cmd_tlm_files = []
        cmd_tlm_dir = os.path.join(self.dir, "cmd_tlm")
        if os.path.isdir(cmd_tlm_dir):
            # Grab All *.txt files in the cmd_tlm folder and subfolders
            for filename in glob.glob(os.path.join(cmd_tlm_dir, "**", "*.txt"), recursive=True):
                if os.path.isfile(filename):
                    cmd_tlm_files.append(filename)
            # Grab All *.xtce files in the cmd_tlm folder and subfolders
            for filename in glob.glob(os.path.join(cmd_tlm_dir, "**", "*.xtce"), recursive=True):
                if os.path.isfile(filename):
                    cmd_tlm_files.append(filename)
        cmd_tlm_files.sort()
        self.cmd_tlm_files = cmd_tlm_files

    def add_cmd_tlm_partials(self):
        """Make sure all partials are included in the cmd_tlm list for the hashing sum calculation"""
        partial_files = []
        cmd_tlm_dir = os.path.join(self.dir, "cmd_tlm")
        if os.path.isdir(cmd_tlm_dir):
            # Grab all _*.txt files in the cmd_tlm folder and subfolders
            for filename in glob.glob(os.path.join(cmd_tlm_dir, "**", "_*.txt"), recursive=True):
                partial_files.append(filename)
        partial_files.sort()
        self.cmd_tlm_files = list(dict.fromkeys(self.cmd_tlm_files + partial_files))
