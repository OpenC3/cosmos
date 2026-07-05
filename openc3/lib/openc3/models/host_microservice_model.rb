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

require 'openc3/models/model'

module OpenC3
  # Captures the information openc3-app needs to spawn a COSMOS interface on the
  # host computer (outside Docker) so it can reach hardware such as serial ports
  # that aren't available inside a container. A host microservice performs raw
  # data transfer and basic functionality only; complex processing (protocols,
  # target definitions) stays on the Docker side of COSMOS. The host side speaks
  # Iroh back to openc3-app which forwards the data into COSMOS through the named
  # bridge_microservice relay.
  #
  # This model is written by InterfaceModel#deploy for bridged interfaces (those
  # configured with the BRIDGE keyword) and read by openc3-app. It is deliberately
  # kept separate from MicroserviceModel so it is NOT run by the normal COSMOS
  # microservice operator.
  class HostMicroserviceModel < Model
    PRIMARY_KEY = 'openc3_host_microservices'

    # The real interface class and its parameters, e.g. ['serial_interface.py', ...]
    attr_accessor :config_params
    attr_accessor :work_dir
    attr_accessor :env
    attr_accessor :options
    attr_accessor :secret_options
    attr_accessor :secrets
    attr_accessor :container
    attr_accessor :needs_dependencies
    # The bridge (bridge_microservice relay) this host interface routes through.
    attr_accessor :bridge_name
    # The Iroh ALPN stream name (the interface name) used to route data back to
    # openc3-app and on to the matching COSMOS bridge_interface.
    attr_accessor :stream

    # NOTE: The following three class methods are reimplemented (like other
    # scoped models) so the ModelController and Model class methods work.
    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end
    # END NOTE

    def initialize(
      name:,
      bridge_name:,
      stream:,
      config_params: [],
      work_dir: '.',
      env: {},
      options: [],
      secret_options: [],
      secrets: [],
      container: nil,
      needs_dependencies: false,
      updated_at: nil,
      plugin: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      @bridge_name = bridge_name
      @stream = stream
      @config_params = config_params
      @work_dir = work_dir
      @env = env
      @options = options
      @secret_options = secret_options
      @secrets = secrets
      @container = container
      @needs_dependencies = needs_dependencies
    end

    def as_json(*a)
      {
        'name' => @name,
        'bridge_name' => @bridge_name,
        'stream' => @stream,
        'config_params' => @config_params,
        'work_dir' => @work_dir,
        'env' => @env,
        'options' => @options,
        'secret_options' => @secret_options,
        'secrets' => @secrets.as_json(*a),
        'container' => @container,
        'needs_dependencies' => @needs_dependencies,
        'plugin' => @plugin,
        'updated_at' => @updated_at
      }
    end
  end
end
