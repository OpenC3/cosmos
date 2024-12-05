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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_module, filename_to_class_name
from openc3.processors.processor import Processor


class ProcessorParser:
    # @param parser [ConfigParser] Configuration parser
    # @param packet [Packet] The current packet
    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    @classmethod
    def parse(cls, parser, packet, cmd_or_tlm):
        parser = ProcessorParser(parser)
        parser.verify_parameters(cmd_or_tlm)
        parser.create_processor(packet)

    # @param parser [ConfigParser] Configuration parser
    def __init__(self, parser):
        self.parser = parser

    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    def verify_parameters(self, cmd_or_tlm):
        if cmd_or_tlm.upper() == "COMMAND":
            raise self.parser.error("PROCESSOR only applies to telemetry packets")

        self.usage = "PROCESSOR <PROCESSOR NAME> <PROCESSOR CLASS FILENAME> <PROCESSOR SPECIFIC OPTIONS>"
        self.parser.verify_num_parameters(2, None, self.usage)

    # @param packet [Packet] The packet the processor should be added to
    def create_processor(self, packet):
        try:
            klass = get_class_from_module(
                filename_to_module(self.parser.parameters[1]),
                filename_to_class_name(self.parser.parameters[1]),
            )

            if len(self.parser.parameters) > 2:
                processor = klass(*self.parser.parameters[2 : (len(self.parser.parameters))])
            else:
                processor = klass()
            if not isinstance(processor, Processor):
                raise TypeError(f"processor must be a Processor but is a {processor.__class__.__name__}")

            processor.name = self._get_processor_name()
            packet.processors[processor.name] = processor
        except Exception as err:
            raise self.parser.error(err, self.usage)

    def _get_processor_name(self):
        return self.parser.parameters[0].upper()
