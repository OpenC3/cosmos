# encoding: ascii-8bit

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

require 'openc3/utilities/secrets'

# Mixin providing plugin.txt keyword handling shared by the models the operator
# turns into running containers (InterfaceModel / RouterModel and
# MicroserviceModel). Including classes must initialize @ports to an Array.
module OpenC3
  module ConfigKeywordModel
    # Parse a PORT keyword, appending [number, protocol] to @ports.
    def parse_port(parser, keyword, parameters)
      usage = "PORT <Number> <Protocol (Optional)"
      parser.verify_num_parameters(1, 2, usage)
      begin
        @ports << [Integer(parameters[0])]
      rescue # In case Integer fails
        raise ConfigParser::Error.new(parser, "Port must be an integer: #{parameters[0]}", usage)
      end
      protocol = ConfigParser.handle_nil(parameters[1])
      if protocol
        # Per https://kubernetes.io/docs/concepts/services-networking/service/#protocol-support
        if %w(TCP UDP SCTP).include?(protocol.upcase)
          @ports[-1] << protocol.upcase
        else
          raise ConfigParser::Error.new(parser, "Unknown port protocol: #{parameters[1]}", usage)
        end
      else
        @ports[-1] << 'TCP'
      end
    end

    # Validate a SECRET / BRIDGE_SECRET definition. FILE type paths are restricted
    # to Secrets.secret_file_dir to prevent reading or overwriting arbitrary files.
    def validate_secret(parser, keyword, parameters)
      type = parameters[0].to_s.upcase
      unless ['ENV', 'FILE'].include?(type)
        raise ConfigParser::Error.new(parser, "Unknown secret type '#{parameters[0]}' for #{keyword}. Must be ENV or FILE.")
      end
      # Normalize in place so the stored secret matches what the operator and
      # Secrets.setup match on, both of which compare against 'ENV' / 'FILE' and
      # use the path exactly as given.
      parameters[0] = type
      if type == 'FILE'
        begin
          parameters[2] = Secrets.validate_file_path(parameters[2])
        rescue ArgumentError => error
          raise ConfigParser::Error.new(parser, "#{keyword} #{error.message}")
        end
      end
    end
  end
end
