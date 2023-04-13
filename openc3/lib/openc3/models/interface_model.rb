# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'
require 'openc3/models/microservice_model'
require 'openc3/models/target_model'

module OpenC3
  class InterfaceModel < Model
    INTERFACES_PRIMARY_KEY = 'openc3_interfaces'
    ROUTERS_PRIMARY_KEY = 'openc3_routers'

    attr_accessor :config_params
    attr_accessor :target_names # Redundant superset of cmd_target_names and tlm_target_names for backwards compat
    attr_accessor :cmd_target_names
    attr_accessor :tlm_target_names
    attr_accessor :connect_on_startup
    attr_accessor :auto_reconnect
    attr_accessor :reconnect_delay
    attr_accessor :disable_disconnect
    attr_accessor :options
    attr_accessor :secret_options
    attr_accessor :protocols
    attr_accessor :interfaces
    attr_accessor :log_stream
    attr_accessor :needs_dependencies
    attr_accessor :secrets

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      super("#{scope}__#{_get_key}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{_get_key}")
    end

    def self.all(scope:)
      super("#{scope}__#{_get_key}")
    end
    # END NOTE

    # Called by the PluginModel to allow this class to validate it's top-level keyword: "INTERFACE"
    # Interface/Router specific keywords are handled by the instance method "handle_config"
    # NOTE: See RouterModel for the router method implementation
    def self.handle_config(parser, keyword, parameters, plugin: nil, needs_dependencies: false, scope:)
      case keyword
      when 'INTERFACE'
        parser.verify_num_parameters(2, nil, "INTERFACE <Name> <Filename> <Specific Parameters>")
        return self.new(name: parameters[0].upcase, config_params: parameters[1..-1], plugin: plugin, needs_dependencies: needs_dependencies, scope: scope)
      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Interface: #{keyword} #{parameters.join(" ")}")
      end
    end

    # Helper method to return the correct type based on class name
    def self._get_type
      self.name.to_s.split("Model")[0].upcase.split("::")[-1]
    end

    # Helper method to return the correct primary key based on class name
    def self._get_key
      type = _get_type
      case type
      when 'INTERFACE'
        INTERFACES_PRIMARY_KEY
      when 'ROUTER'
        ROUTERS_PRIMARY_KEY
      else
        raise "Unknown type #{type} from class #{self.name}"
      end
    end

    def initialize(
      name:,
      config_params: [],
      target_names: [],
      cmd_target_names: [],
      tlm_target_names: [],
      connect_on_startup: true,
      auto_reconnect: true,
      reconnect_delay: 5.0,
      disable_disconnect: false,
      options: [],
      secret_options: [],
      protocols: [],
      log_stream: nil,
      updated_at: nil,
      plugin: nil,
      needs_dependencies: false,
      secrets: [],
      scope:
    )
      if self.class._get_type == 'INTERFACE'
        super("#{scope}__#{INTERFACES_PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      else
        super("#{scope}__#{ROUTERS_PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      end
      @config_params = config_params
      @target_names = target_names
      @cmd_target_names = cmd_target_names
      @tlm_target_names = tlm_target_names
      @connect_on_startup = connect_on_startup
      @auto_reconnect = auto_reconnect
      @reconnect_delay = reconnect_delay
      @disable_disconnect = disable_disconnect
      @options = options
      @secret_options = secret_options
      @protocols = protocols
      @log_stream = log_stream
      @needs_dependencies = needs_dependencies
      @secrets = secrets
    end

    # Called by InterfaceMicroservice to instantiate the Interface defined
    # by the model configuration. Must be called after get_model which
    # calls from_json to instantiate the class and populate the attributes.
    def build
      klass = OpenC3.require_class(@config_params[0])
      if @config_params.length > 1
        interface_or_router = klass.new(*@config_params[1..-1])
      else
        interface_or_router = klass.new
      end
      interface_or_router.secrets.setup(@secrets)
      interface_or_router.target_names = @target_names.dup
      interface_or_router.cmd_target_names = @cmd_target_names.dup
      interface_or_router.tlm_target_names = @tlm_target_names.dup
      interface_or_router.connect_on_startup = @connect_on_startup
      interface_or_router.auto_reconnect = @auto_reconnect
      interface_or_router.reconnect_delay = @reconnect_delay
      interface_or_router.disable_disconnect = @disable_disconnect
      @options.each do |option|
        interface_or_router.set_option(option[0], option[1..-1])
      end
      @secret_options.each do |option|
        secret_name = option[1]
        secret_value = interface_or_router.secrets.get(secret_name, scope: @scope)
        interface_or_router.set_option(option[0], [secret_value])
      end
      @protocols.each do |protocol|
        klass = OpenC3.require_class(protocol[1])
        interface_or_router.add_protocol(klass, protocol[2..-1], protocol[0].upcase.intern)
      end
      if @log_stream
        interface_or_router.stream_log_pair = StreamLogPair.new(interface_or_router.name, @log_stream)
        interface_or_router.start_raw_logging
      end
      interface_or_router
    end

    def as_json(*a)
      {
        'name' => @name,
        'config_params' => @config_params,
        'target_names' => @target_names,
        'cmd_target_names' => @cmd_target_names,
        'tlm_target_names' => @tlm_target_names,
        'connect_on_startup' => @connect_on_startup,
        'auto_reconnect' => @auto_reconnect,
        'reconnect_delay' => @reconnect_delay,
        'disable_disconnect' => @disable_disconnect,
        'options' => @options,
        'secret_options' => @secret_options,
        'protocols' => @protocols,
        'log_stream' => @log_stream,
        'plugin' => @plugin,
        'needs_dependencies' => @needs_dependencies,
        'secrets' => @secrets.as_json(*a),
        'updated_at' => @updated_at
      }
    end

    def ensure_target_exists(target_name)
      target = TargetModel.get(name: target_name, scope: @scope)
      raise "Target #{target_name} does not exist" unless target
      target
    end

    # Handles Interface/Router specific configuration keywords
    def handle_config(parser, keyword, parameters)
      case keyword
      when 'MAP_TARGET'
        parser.verify_num_parameters(1, 1, "#{keyword} <Target Name>")
        target_name = parameters[0].upcase
        @target_names << target_name unless @target_names.include?(target_name)
        @cmd_target_names << target_name unless @cmd_target_names.include?(target_name)
        @tlm_target_names << target_name unless @tlm_target_names.include?(target_name)

      when 'MAP_CMD_TARGET'
        parser.verify_num_parameters(1, 1, "#{keyword} <Target Name>")
        target_name = parameters[0].upcase
        @target_names << target_name unless @target_names.include?(target_name)
        @cmd_target_names << target_name unless @cmd_target_names.include?(target_name)

      when 'MAP_TLM_TARGET'
        parser.verify_num_parameters(1, 1, "#{keyword} <Target Name>")
        target_name = parameters[0].upcase
        @target_names << target_name unless @target_names.include?(target_name)
        @tlm_target_names << target_name unless @tlm_target_names.include?(target_name)

      when 'DONT_CONNECT'
        parser.verify_num_parameters(0, 0, "#{keyword}")
        @connect_on_startup = false

      when 'DONT_RECONNECT'
        parser.verify_num_parameters(0, 0, "#{keyword}")
        @auto_reconnect = false

      when 'RECONNECT_DELAY'
        parser.verify_num_parameters(1, 1, "#{keyword} <Delay in Seconds>")
        @reconnect_delay = Float(parameters[0])

      when 'DISABLE_DISCONNECT'
        parser.verify_num_parameters(0, 0, "#{keyword}")
        @disable_disconnect = true

      when 'OPTION'
        parser.verify_num_parameters(2, nil, "#{keyword} <Option Name> <Option Value 1> <Option Value 2 (optional)> <etc>")
        @options << parameters.dup

      when 'PROTOCOL'
        usage = "#{keyword} <READ WRITE READ_WRITE> <protocol filename or classname> <Protocol specific parameters>"
        parser.verify_num_parameters(2, nil, usage)
        unless %w(READ WRITE READ_WRITE).include? parameters[0].upcase
          raise parser.error("Invalid protocol type: #{parameters[0]}", usage)
        end

        @protocols << parameters.dup

      when 'LOG_STREAM', 'LOG_RAW'
        parser.verify_num_parameters(0, nil, "#{keyword} <Log Stream Class File (optional)> <Log Stream Parameters (optional)>")
        @log_stream = parameters.dup # Even if it is empty we copy it to set it as not nil

      when 'DONT_LOG'
        Logger.warn "DONT_LOG is deprecated and does nothing."

      when 'SECRET'
        parser.verify_num_parameters(3, 5, "#{keyword} <Secret Type: ENV or FILE> <Secret Name> <Environment Variable Name or File Path> <Option Name (Optional)> <Secret Store Name (Optional)>")
        @secrets << parameters[0..2]
        if ConfigParser.handle_nil(parameters[3])
          # Option Name, Secret Name
          @secret_options << [parameters[3], parameters[1]]
        end
        if ConfigParser.handle_nil(parameters[4])
          @secrets[-1] << parameters[4]
        end

      else
        raise ConfigParser::Error.new(parser, "Unknown keyword and parameters for Interface/Router: #{keyword} #{parameters.join(" ")}")

      end

      return nil
    end

    # Creates a MicroserviceModel to deploy the Interface/Router
    def deploy(gem_path, variables, validate_only: false)
      type = self.class._get_type
      microservice_name = "#{@scope}__#{type}__#{@name}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        work_dir: '/openc3/lib/openc3/microservices',
        cmd: ["ruby", "#{type.downcase}_microservice.rb", microservice_name],
        target_names: @target_names,
        plugin: @plugin,
        needs_dependencies: @needs_dependencies,
        secrets: @secrets,
        scope: @scope
      )
      unless validate_only
        @target_names.each { |target_name| ensure_target_exists(target_name) }
        microservice.create
        microservice.deploy(gem_path, variables)
        ConfigTopic.write({ kind: 'created', type: type.downcase, name: @name, plugin: @plugin }, scope: @scope)
        Logger.info "Configured #{type.downcase} microservice #{microservice_name}"
      end
      microservice
    end

    # Looks up the deployed MicroserviceModel and destroy the microservice model
    # should should trigger the operator to kill the microservice that in turn
    # will destroy the InterfaceStatusModel when a stop is called.
    def undeploy
      type = self.class._get_type
      name = "#{@scope}__#{type}__#{@name}"
      model = MicroserviceModel.get_model(name: name, scope: @scope)
      if model
        model.destroy
        ConfigTopic.write({ kind: 'deleted', type: type.downcase, name: @name, plugin: @plugin }, scope: @scope)
      end

      if type == 'INTERFACE'
        status_model = InterfaceStatusModel.get_model(name: @name, scope: @scope)
      else
        status_model = RouterStatusModel.get_model(name: @name, scope: @scope)
      end
      status_model.destroy if status_model
    end

    def unmap_target(target_name, cmd_only: false, tlm_only: false)
      if cmd_only and tlm_only
        cmd_only = false
        tlm_only = false
      end
      target_name = target_name.to_s.upcase

      # Remove from this interface
      if cmd_only
        @cmd_target_names.delete(target_name)
        @target_names.delete(target_name) unless @tlm_target_names.include?(target_name)
      elsif tlm_only
        @tlm_target_names.delete(target_name)
        @target_names.delete(target_name) unless @cmd_target_names.include?(target_name)
      else
        @cmd_target_names.delete(target_name)
        @tlm_target_names.delete(target_name)
        @target_names.delete(target_name)
      end
      update()

      # Respawn the microservice
      type = self.class._get_type
      microservice_name = "#{@scope}__#{type}__#{@name}"
      microservice = MicroserviceModel.get_model(name: microservice_name, scope: scope)
      microservice.target_names.delete(target_name) unless @target_names.include?(target_name)
      microservice.update
    end

    def map_target(target_name, cmd_only: false, tlm_only: false, unmap_old: true)
      if cmd_only and tlm_only
        cmd_only = false
        tlm_only = false
      end
      target_name = target_name.to_s.upcase
      ensure_target_exists(target_name)

      if unmap_old
        # Remove from old interface
        all_interfaces = InterfaceModel.all(scope: scope)
        old_interface = nil
        all_interfaces.each do |old_interface_name, old_interface_details|
          if old_interface_details['target_names'].include?(target_name)
            old_interface = InterfaceModel.from_json(old_interface_details, scope: scope)
            old_interface.unmap_target(target_name, cmd_only: cmd_only, tlm_only: tlm_only) if old_interface
          end
        end
      end

      # Add to this interface
      @target_names << target_name unless @target_names.include?(target_name)
      @cmd_target_names << target_name unless @cmd_target_names.include?(target_name) or tlm_only
      @tlm_target_names << target_name unless @tlm_target_names.include?(target_name) or cmd_only
      update()

      # Respawn the microservice
      type = self.class._get_type
      microservice_name = "#{@scope}__#{type}__#{@name}"
      microservice = MicroserviceModel.get_model(name: microservice_name, scope: scope)
      microservice.target_names << target_name unless microservice.target_names.include?(target_name)
      microservice.update
    end
  end
end
