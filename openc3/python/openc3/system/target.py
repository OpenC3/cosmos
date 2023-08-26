# Copyright 2023 OpenC3, Inc.
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

import os
import glob
from openc3.top_level import add_to_search_path
from openc3.utilities.logger import Logger
from openc3.config.config_parser import ConfigParser


class Target:
    """Target encapsulates the information about a OpenC3 target. Targets are
    accessed through interfaces and have command and telemetry definition files
    which define their access."""

    def __init__(self, target_name, path, gem_path=None):
        """Creates a new target by processing the target.txt file in the directory
        given by the path joined with the target_name. Records all the command
        and telemetry definition files found in the targets cmd_tlm directory.
        System uses this list and processes them using PacketConfig."""
        self.requires = []
        self.ignored_parameters = []
        self.ignored_items = []
        self.cmd_tlm_files = []
        self.interface = None
        self.routers = []
        self.cmd_cnt = 0
        self.tlm_cnt = 0
        self.cmd_unique_id_mode = False
        self.tlm_unique_id_mode = False
        self.name = target_name.upper()
        self.get_target_dir(path, gem_path)
        self.process_target_config_file()

        # If target.txt didn't specify specific cmd/tlm files then add everything
        if len(self.cmd_tlm_files) == 0:
            self.cmd_tlm_files = self.add_all_cmd_tlm()
        else:
            self.cmd_tlm_files = self.add_cmd_tlm_partials()

    # Parses the target configuration file
    #
    # self.param filename [String] The target configuration file to parse
    def process_file(self, filename):
        Logger.info(f"Processing target definition in file '{filename}'")
        parser = ConfigParser("https://openc3.com/docs/v5/target")
        for keyword, parameters in parser.parse_file(filename):
            match keyword:
                case "REQUIRE":
                    usage = f"{keyword} <FILENAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    filename = f"{self.dir}/lib{parameters[0]}"
                    # TODO:
                    # try:
                    #     # Require absolute path to file in target lib folder. Prevents name
                    #     # conflicts at the require step
                    #     # OpenC3.require_file(filename, False)

                    # except LoadError:
                    #     begin
                    #     # If we couldn't load at the target/lib level check everywhere
                    #     OpenC3.disable_warnings do
                    #         filename = parameters[0]
                    #         OpenC3.require_file(parameters[0])

                    #     rescue Exception => err
                    #     raise parser.error(err)

                    # rescue Exception => err
                    #     raise parser.error(err)

                    # This code resolves any relative paths to absolute before putting into the self.requires array
                    # unless Pathname.new(filename).absolute?
                    #     $:.each do |search_path|
                    #     test_filename = os.path.join(search_path, filename).gsub("\\", "/")
                    #     if os.path.exists(test_filename)
                    #         filename = test_filename
                    #         break
                    # self.requires << filename

                case "IGNORE_PARAMETER" | "IGNORE_ITEM":
                    usage = "{keyword} <{keyword.split('_')[1]} NAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    if "PARAMETER" in keyword:
                        self.ignored_parameters.append(parameters[0].upper())
                    if "ITEM" in keyword:
                        self.ignored_items.append(parameters[0].upper())

                case "COMMANDS" | "TELEMETRY":
                    usage = "{keyword} <FILENAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    filename = f"{self.dir}/cmd_tlm/{parameters[0]}"
                    if not os.path.exists(filename):
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
        config = {}
        config["name"] = self.name
        config["requires"] = self.requires
        config["ignored_parameters"] = self.ignored_parameters
        config["ignored_items"] = self.ignored_items
        # config['auto_screen_substitute'] = True if self.auto_screen_substitute
        config["cmd_tlm_files"] = self.cmd_tlm_files
        # config['filename'] = self.filename
        # config['interface'] = self.interface.name if self.interface
        # config['dir'] = self.dir
        # config['cmd_cnt'] = self.cmd_cnt
        # config['tlm_cnt'] = self.tlm_cnt
        if self.cmd_unique_id_mode:
            config["cmd_unique_id_mode"] = True
        if self.tlm_unique_id_mode:
            config["tlm_unique_id_mode"] = True
        config["id"] = self.id
        return config

    # Get the target directory and add the target's lib folder to the
    # search path if it exists
    def get_target_dir(self, path, gem_path):
        if gem_path:
            self.dir = gem_path
        else:
            self.dir = os.path.join(path, self.name)

        #   self.dir.gsub!("\\", '/')
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
        if os.path.exists(os.path.join(self.dir, "cmd_tlm")):
            # Grab All *.txt files in the cmd_tlm folder and subfolders
            for filename in glob.glob(
                os.path.join(self.dir, "cmd_tlm", "**", "*.txt"), recursive=True
            ):
                if os.path.isfile(filename):
                    cmd_tlm_files.append(filename)
            # Grab All *.xtce files in the cmd_tlm folder and subfolders
            for filename in glob.glob(
                os.path.join(self.dir, "cmd_tlm", "**", "*.xtce"), recursive=True
            ):
                if os.isfile(filename):
                    cmd_tlm_files.append(filename)
        cmd_tlm_files.sort()
        return cmd_tlm_files

    # Make sure all partials are included in the cmd_tlm list for the hashing sum calculation
    def add_cmd_tlm_partials(self):
        partial_files = []
        if os.path.isfile(os.path.join(self.dir, "cmd_tlm")):
            # Grab all _*.txt files in the cmd_tlm folder and subfolders
            for filename in glob.glob(
                os.path.join(self.dir, "cmd_tlm", "**", "_*.txt"), recursive=True
            ):
                partial_files.append(filename)
        partial_files.sort()
        self.cmd_tlm_files = self.cmd_tlm_files + partial_files
        self.cmd_tlm_files = list(set(self.cmd_tlm_files))
