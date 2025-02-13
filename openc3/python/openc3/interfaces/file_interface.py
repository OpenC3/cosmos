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

from openc3.interfaces.interface import Interface
from openc3.config.config_parser import ConfigParser
from openc3.utilities.string import class_name_to_filename
from openc3.top_level import get_class_from_module
from openc3.utilities.string import build_timestamped_filename
import queue
import os
import pathlib
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer
from watchdog.observers.polling import PollingObserver


class NewFileEventHandler(FileSystemEventHandler):
    def __init__(self, interface):
        self.interface = interface

    def on_any_event(self, event: FileSystemEvent) -> None:
        if event.event_type == "created" or (
            event.event_type == "moved" and event.dest_path == self.interface.telemetry_read_folder
        ):
            self.interface.queue.put(event.src_path)


class FileInterface(Interface):
    # @param command_write_folder [String] Folder to write command files to - Set to None to disallow writes
    # @param telemetry_read_folder [String] Folder to read telemetry files from - Set to None to disallow reads
    # @param telemetry_archive_folder [String] Folder to move read telemetry files to - Set to DELETE to delete files
    # @param file_read_size [Integer] Number of bytes to read from the file at a time
    # @param stored [Boolean] Whether to set stored flag on read telemetry
    # @param protocol_type [String] Name of the protocol to use
    #   with this interface
    # @param protocol_args [Array<String>] Arguments to pass to the protocol
    def __init__(
        self,
        command_write_folder,
        telemetry_read_folder,
        telemetry_archive_folder,
        file_read_size=65536,
        stored=True,
        protocol_type=None,
        protocol_args=[],
    ):
        super().__init__()

        self.protocol_type = ConfigParser.handle_none(protocol_type)
        self.protocol_args = protocol_args
        if self.protocol_type:
            protocol_class_name = str(protocol_type).capitalize() + "Protocol"
            filename = class_name_to_filename(protocol_class_name)
            klass = get_class_from_module(f"openc3.interfaces.protocols.{filename}", protocol_class_name)
            self.add_protocol(klass, protocol_args, "PARAMS")

        self.command_write_folder = ConfigParser.handle_none(command_write_folder)
        self.telemetry_read_folder = ConfigParser.handle_none(telemetry_read_folder)
        self.telemetry_archive_folder = ConfigParser.handle_none(telemetry_archive_folder)
        self.file_read_size = int(file_read_size)
        self.stored = ConfigParser.handle_true_false(stored)

        if not self.telemetry_read_folder:
            self.read_allowed = False
        if not self.command_write_folder:
            self.write_allowed = False
        if not self.command_write_folder:
            self.write_raw_allowed = False

        self.file = None
        self.file_path = None
        self.listener = None
        self._connected = False
        self.extension = ".bin"
        self.label = "command"
        self.queue = queue.Queue()
        self.polling = False
        self.recursive = False

    def connect(self):
        super().connect() # Reset the protocols

        if self.telemetry_read_folder:
            event_handler = NewFileEventHandler(self)
            if self.polling:
                self.listener = PollingObserver()
            else:
                self.listener = Observer()
            self.listener.schedule(event_handler, self.telemetry_read_folder, recursive=self.recursive)
            self.listener.start()

        self._connected = True

    def connected(self):
        return self._connected

    def disconnect(self):
        if self.file and not self.file.closed:
            self.file.close()
        self.file = None
        self.file_path = None
        if self.listener:
            self.listener.stop()
        self.listener = None
        self.queue.put(None)
        super().disconnect()
        self._connected = False

    def read_interface(self):
        while True:
            if self.file:
                # Read more data from existing file
                data = self.file.read(self.file_read_size)
                if data is not None and len(data) > 0:
                    self.read_interface_base(data, None)
                    return data, None
                else:
                    self.finish_file()

            # Find the next file to read
            file = self.get_next_telemetry_file()
            if file:
                print(f"Open: {file}")
                self.file = open(file, "rb")
                self.file_path = file
                continue

            # Wait for a file to read
            result = self.queue.get()
            if result is None:
                return None, None

    def write_interface(self, data, extra=None):
        # Write this data into its own file
        with open(self.create_unique_filename(), "wb") as file:
            file.write(data)

        self.write_interface_base(data, extra)
        return data, extra

    def convert_data_to_packet(self, data, extra=None):
        packet = super().convert_data_to_packet(data, extra)
        if packet and self.stored:
            packet.stored = True

        return packet

    # Supported Options
    # LABEL - Label to add to written files
    # EXTENSION - Extension to add to written files
    # (see Interface#set_option)
    def set_option(self, option_name, option_values):
        super().set_option(option_name, option_values)
        match option_name.upper():
            case "LABEL":
                self.label = option_values[0]
            case "EXTENSION":
                self.extension = option_values[0]
            case "POLLING":
                self.polling = ConfigParser.handle_true_false(option_values[0])
            case "RECURSIVE":
                self.recursive = ConfigParser.handle_true_false(option_values[0])

    def finish_file(self):
        self.file.close()
        self.file = None

        # Archive (or DELETE) complete file
        if self.telemetry_archive_folder == "DELETE":
            os.remove(self.file_path)
        else:
            new_path = os.path.join(self.telemetry_archive_folder, os.path.basename(self.file_path))
            os.rename(self.file_path, new_path)
        self.file_path = None

    def get_next_telemetry_file(self):
        if self.recursive:
            path = pathlib.Path(self.telemetry_read_folder)
            list = [str(item) for item in path.rglob("*") if item.is_file()]
        else:
            list = os.listdir(self.telemetry_read_folder)
        list.sort()
        if len(list) > 0:
            if self.recursive:
                return list[0]
            else:
                return os.path.join(self.telemetry_read_folder, list[0])
        else:
            return None

    def create_unique_filename(self):
        # Create a filename that doesn't exist
        attempt = None
        while True:
            filename = os.path.join(
                self.command_write_folder,
                build_timestamped_filename([self.label, attempt], self.extension),
            )
            if os.path.isfile(filename):
                if attempt is None:
                    attempt = 0
                attempt += 1
            else:
                return filename
