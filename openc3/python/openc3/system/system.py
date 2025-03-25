# Copyright 2025 OpenC3, Inc.
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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

import os
import glob
import zipfile
import traceback
from threading import Lock
from openc3.environment import OPENC3_SCOPE, OPENC3_CONFIG_BUCKET
from openc3.top_level import add_to_search_path
from openc3.utilities.bucket import Bucket
from openc3.utilities.logger import Logger
from openc3.utilities.store import Store
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig
from openc3.packets.commands import Commands
from openc3.packets.telemetry import Telemetry
from openc3.packets.limits import Limits
from openc3.system.target import Target


class System:
    # Declare the System class variables ... they are set in __init__
    targets = {}
    packet_config = None
    commands = None
    telemetry = None
    limits = None

    # Variable that holds the singleton instance
    instance_obj = None

    # Mutex used to ensure that only one instance of System is created
    instance_mutex = Lock()

    # Callbacks to call once instance_obj is created
    post_instance_callbacks = []

    @classmethod
    def limits_set(cls, scope=OPENC3_SCOPE):
        """This line is basically the same code as limits_event_topic.py,
        but we can't import it because it imports system.py and that
        creates a circular reference

        Return:
            [Symbol] The current limits_set of the system returned from Redis
        """
        sets = Store.hgetall(f"{scope}__limits_sets")
        try:
            return list(sets.keys())[list(sets.values()).index(b"true")].decode()
        except ValueError:
            return "DEFAULT"

    @classmethod
    def add_post_instance_callback(cls, callback):
        if System.obj_instance:
            callback()
        else:
            cls.post_instance_callbacks << callback

    @classmethod
    def setup_targets(cls, target_names, base_dir, scope=OPENC3_SCOPE):
        if not System.instance_obj:
            os.makedirs(f"{base_dir}/targets", exist_ok=True)
            bucket = Bucket.getClient()
            for target_name in target_names:
                # Retrieve bucket/targets/target_name/<TARGET>_current.zip
                zip_path = f"{base_dir}/targets/{target_name}_current.zip"
                bucket_key = f"{scope}/target_archives/{target_name}/{target_name}_current.zip"
                Logger.info(f"Retrieving {bucket_key} from targets bucket")
                bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=bucket_key, path=zip_path)
                with zipfile.ZipFile(zip_path) as zip_file:
                    zip_file.extractall(f"{base_dir}/targets")

                # Now add any modifications in targets_modified/TARGET/cmd_tlm
                # This adds support for remembering dynamically created packets
                # target.txt must be configured to either use all files in cmd_tlm folder (default)
                # or have a predetermined empty file like dynamic_tlm.txt
                bucket_path = f"{scope}/targets_modified/{target_name}/cmd_tlm"
                _, files = bucket.list_files(bucket=OPENC3_CONFIG_BUCKET, path=bucket_path)
                for file in files:
                    bucket_key = os.path.join(bucket_path, file["name"])
                    local_path = f"{base_dir}/targets/{target_name}/cmd_tlm/{file['name']}"
                    bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=bucket_key, path=local_path)

            # Build System from targets
            System.instance(target_names, f"{base_dir}/targets")

    @classmethod
    def instance(cls, target_names=None, target_config_dir=None):
        """Get the singleton instance of System

        Args:
            target_names [Array of target_names]
            target_config_dir Directory where target config folders are

        Returns:
            [System] The System singleton
        """
        if System.instance_obj:
            return System.instance_obj
        if not target_names and not target_config_dir:
            raise Exception("System.instance parameters are required on first call")

        with System.instance_mutex:
            if System.instance_obj:
                return System.instance_obj
            System.instance_obj = cls(target_names, target_config_dir)
            for callback in System.post_instance_callbacks:
                callback()
            return System.instance_obj

    # Dynamically add packets to the system instance
    #
    # @param dynamic_packets [Array of packets]
    # @param cmd_or_tlm [Symbol] :COMMAND or :TELEMETRY
    # @param affect_ids [Boolean] Whether to affect packet id lookup or not
    @classmethod
    def dynamic_update(cls, dynamic_packets, cmd_or_tlm="TELEMETRY", affect_ids=False):
        for packet in dynamic_packets:
            if cmd_or_tlm == "TELEMETRY":
                System.instance_obj.telemetry.dynamic_add_packet(packet, affect_ids=affect_ids)
            else:
                System.instance_obj.commands.dynamic_add_packet(packet, affect_ids=affect_ids)

    # Create a new System object.
    #
    # @param target_names [Array of target names]
    # @param target_config_dir Directory where target config folders are
    def __init__(self, target_names, target_config_dir):
        # Find all the base gem lib directories and add them to the search path
        # Ruby handles this because the gem is installed so lib is in the path
        for path in glob.glob("/gems/gems/**/lib"):
            add_to_search_path(path, True)
        if target_config_dir:
            add_to_search_path(target_config_dir, True)
        System.targets = {}
        System.packet_config = PacketConfig()
        System.commands = Commands(System.packet_config, System)
        System.telemetry = Telemetry(System.packet_config, System)
        System.limits = Limits(System.packet_config, System)
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
            trace = "".join(traceback.TracebackException.from_exception(error).format())
            errors.append(f"Error processing {target_name}:\n{trace}")
        if len(errors) != 0:
            raise Exception("\n".join(errors))
