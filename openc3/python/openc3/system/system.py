# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import zipfile
from threading import Lock
from openc3.environment import OPENC3_SCOPE, OPENC3_CONFIG_BUCKET
from openc3.top_level import add_to_search_path
from openc3.utilities.bucket import Bucket
from openc3.utilities.logger import Logger
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig
from openc3.packets.commands import Commands
from openc3.packets.telemetry import Telemetry
from openc3.packets.limits import Limits
from .target import Target


class System:
    targets = {}
    packet_config = PacketConfig()
    commands = Commands(packet_config)
    telemetry = None
    limits = Limits(packet_config)

    # Variable that holds the singleton instance
    instance_obj = None

    # Mutex used to ensure that only one instance of System is created
    instance_mutex = Lock()

    # The current limits set
    limits_set = None

    # @return [Symbol] The current limits_set of the system returned from Redis
    @classmethod
    def limits_set(cls):
        # TODO: Implement LimitsEventTopic
        # if not System.limits_set:
        #   System.limits_set = LimitsEventTopic.current_set(scope=OPENC3_SCOPE)
        return System.limits_set

    @classmethod
    def setup_targets(cls, target_names, base_dir, scope=OPENC3_SCOPE):
        if not System.instance_obj:
            os.makedirs(f"{base_dir}/targets", exist_ok=True)
            bucket = Bucket.getClient()
            for target_name in target_names:
                # Retrieve bucket/targets/target_name/target_id.zip
                zip_path = f"{base_dir}/targets/{target_name}_current.zip"
                bucket_key = (
                    f"{scope}/target_archives/{target_name}/{target_name}_current.zip"
                )
                Logger.info(f"Retrieving {bucket_key} from targets bucket")
                bucket.get_object(
                    bucket=OPENC3_CONFIG_BUCKET, key=bucket_key, path=zip_path
                )
                with zipfile.ZipFile(zip_path) as zip_file:
                    for entry in zip_file.namelist():
                        path = f"{base_dir}/targets/{entry}"
                        os.makedirs(path, exist_ok=True)
                        zip_file.extract(entry, path)
            # Build System from targets
            System.instance(target_names, f"{base_dir}/targets")

    # Get the singleton instance of System
    #
    # @param target_names [Array of target_names]
    # @param target_config_dir Directory where target config folders are
    # @return [System] The System singleton
    @classmethod
    def instance(cls, target_names=None, target_config_dir=None):
        if System.instance_obj:
            return System.instance_obj
        if not target_names and not target_config_dir:
            raise Exception("System.instance parameters are required on first call")

        with System.instance_mutex:
            System.instance_obj = cls(target_names, target_config_dir)
            return System.instance_obj

    # Create a new System object.
    #
    # @param target_names [Array of target names]
    # @param target_config_dir Directory where target config folders are
    def __init__(self, target_names, target_config_dir):
        add_to_search_path(target_config_dir, True)
        System.targets = {}
        System.packet_config = PacketConfig()
        System.commands = Commands(System.packet_config)
        System.telemetry = Telemetry(System.packet_config, System)
        System.limits = Limits(System.packet_config)

        # self.limits = Limits(self.packet_config)
        # System.limits = self.limits
        for target_name in target_names:
            self.add_target(target_name, target_config_dir)

    def add_target(self, target_name, target_config_dir):
        parser = ConfigParser()
        folder_name = f"{target_config_dir}/{target_name}"
        if not os.path.exists(folder_name):
            raise parser.error(f"Target folder must exist '{folder_name}'.")

        target = Target(target_name, target_config_dir)
        System.targets[target.name] = target
        errors = []  # Store all errors processing the cmd_tlm files
        try:
            for cmd_tlm_file in target.cmd_tlm_files:
                self.packet_config.process_file(cmd_tlm_file, target.name)
        except Exception as error:
            errors.append(f"Error processing {cmd_tlm_file}:\n{error}")
        if len(errors) != 0:
            raise Exception("\n".join(errors))
