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

require 'openc3'
require 'openc3/api/api'
require 'openc3/io/json_drb_object'
require 'openc3/script/api_shared'
require 'openc3/script/autonomic'
require 'openc3/script/calendar'
require 'openc3/script/commands'
require 'openc3/script/critical_cmd'
require 'openc3/script/exceptions'
# openc3/script/extract is just helper methods
require 'openc3/script/limits'
require 'openc3/script/metadata'
require 'openc3/script/packages'
require 'openc3/script/plugins'
require 'openc3/script/queue'
require 'openc3/script/screen'
require 'openc3/script/script_runner'
require 'openc3/script/storage'
# openc3/script/suite_results and suite_runner are used by
# running_script.rb and the script_runner_api
# openc3/script/suite is used by end user SR Suites
require 'openc3/script/tables'
require 'openc3/script/telemetry'
require 'openc3/script/web_socket_api'
require 'openc3/utilities/authentication'

$api_server = nil
$script_runner_api_server = nil
$disconnect = false
$openc3_scope = ENV['OPENC3_SCOPE'] || 'DEFAULT'
$openc3_in_cluster = false

module OpenC3
  module Script
    private

    include ApiShared

    # All methods are private so they can only be called by themselves and not
    # on another object. This is important for the JsonDrbObject class which we
    # use to communicate with the server. JsonDrbObject implements method_missing
    # to forward calls to the remote service. If these methods were not private,
    # they would be included on the $api_server global and would be
    # called directly instead of being forwarded over the JsonDrb connection to
    # the real server.

    # For each of the Api methods determine if they haven't previously been defined by
    # one of the script files. If not define them and proxy to the $api_server.
    Api::WHITELIST.each do |method|
      unless private_instance_methods(false).include?(method.intern)
        define_method(method.intern) do |*args, **kwargs, &block|
          kwargs[:scope] = $openc3_scope unless kwargs[:scope]
          $api_server.method_missing(method.intern, *args, **kwargs, &block)
        end
      end
    end

    # Called when this module is mixed in using "include OpenC3::Script"
    def self.included(base)
      initialize_script()
    end

    def initialize_script
      shutdown_script()
      $disconnect = false
      $api_server = ServerProxy.new
      if $api_server.generate_url =~ /openc3-cosmos-cmd-tlm-api/
        $openc3_in_cluster = true
      else
        $openc3_in_cluster = false
      end
      $script_runner_api_server = ScriptServerProxy.new
    end

    def shutdown_script
      $api_server.shutdown if $api_server
      $api_server = nil
      $script_runner_api_server.shutdown if $script_runner_api_server
      $script_runner_api_server = nil
    end

    # Internal method used in scripts when encountering a hazardous command
    # Not part of public APIs but must be implemented here
    def prompt_for_hazardous(target_name, cmd_name, hazardous_description)
      loop do
        message = "Warning: Command #{target_name} #{cmd_name} is Hazardous. "
        message << "\n#{hazardous_description}\n" if hazardous_description
        message << "Send? (y): "
        print message
        answer = gets.chomp
        if answer.downcase == 'y'
          return true
        end
      end
    end

    def prompt_for_critical_cmd(uuid, _username, _target_name, _cmd_name, _cmd_params, cmd_string)
      puts "Waiting for critical command approval:"
      puts "  #{cmd_string}"
      puts "  UUID: #{uuid}"
      loop do
        status = critical_cmd_status(uuid)
        if status == 'APPROVED'
          return
        elsif status == 'REJECTED'
          raise "Critical command rejected"
        end
        # Else still waiting
        wait(0.1)
      end
    end

    ###########################################################################
    # START PUBLIC API
    ###########################################################################

    def disconnect_script
      $disconnect = true
    end

    def ask_string(question, blank_or_default = false, password = false)
      answer = ''
      default = ''
      if blank_or_default != true && blank_or_default != false
        question << " (default = #{blank_or_default})"
        default = blank_or_default.to_s
        allow_blank = true
      else
        allow_blank = blank_or_default
      end
      while answer.empty?
        print question + " "
        answer = gets
        answer.chomp!
        break if allow_blank
      end
      if answer.empty? and !default.empty?
        answer = default
      end
      return answer
    end

    def ask(question, blank_or_default = false, password = false)
      string = ask_string(question, blank_or_default, password)
      value = string.convert_to_value
      return value
    end

    def message_box(string, *buttons, **options)
      print "#{string} (#{buttons.join(", ")}): "
      print "Details: #{details}\n" if options['details']
      gets.chomp
    end

    def vertical_message_box(string, *buttons, **options)
      message_box(string, *buttons, **options)
    end

    def combo_box(string, *items, **options)
      message_box(string, *items, **options)
    end

    def _file_dialog(title, message, filter:)
      answer = ''
      path = "./*"
      path += filter if filter
      files = Dir[path]
      files.select! { |f| !File.directory? f }
      while answer.empty?
        print "#{title}\n#{message}\n#{files.join("\n")}\n<Type file name>:"
        answer = gets
        answer.chomp!
      end
      return answer
    end

    def open_file_dialog(title, message = "Open File", filter:)
      _file_dialog(title, message, filter)
    end

    def open_files_dialog(title, message = "Open File(s)", filter:)
      _file_dialog(title, message, filter)
    end

    def prompt(string, text_color: nil, background_color: nil, font_size: nil, font_family: nil, details: nil)
      print "#{string}: "
      print "Details: #{details}\n" if details
      gets.chomp
    end

    def step_mode
      # NOOP
    end

    def run_mode
      # NOOP
    end

    # Note: Enterprise Only - Use this for first time setup of an offline access token
    # so that users can run scripts.  Not necessary if accessing APIs via the web
    # frontend as it handles it automatically.
    #
    # Example:
    # initialize_offline_access()
    # script_run("INST/procedures/collect.rb")
    #
    def initialize_offline_access
      keycloak_url = ENV['OPENC3_KEYCLOAK_URL']
      if keycloak_url.nil? or keycloak_url.empty?
        raise "initialize_offline_access only valid in COSMOS Enterprise. OPENC3_KEYCLOAK_URL environment variable must be set."
      end
      auth = OpenC3KeycloakAuthentication.new(keycloak_url)
      auth.token(include_bearer: true, openid_scope: 'openid offline_access')
      set_offline_access(auth.refresh_token)
    end

    ###########################################################################
    # END PUBLIC API
    ###########################################################################
  end

  # Provides a proxy to the JsonDRbObject which communicates with the API server
  class ServerProxy
    # pull openc3-cosmos-cmd-tlm-api url from environment variables
    def generate_url
      schema = ENV['OPENC3_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-cmd-tlm-api')
      port = ENV['OPENC3_API_PORT'] || '2901'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}"
    end

    # pull openc3-cosmos-cmd-tlm-api timeout from environment variables
    def generate_timeout
      timeout = ENV['OPENC3_API_TIMEOUT'] || '1.0'
      return timeout.to_f
    end

    # generate the auth object
    def generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD']
          return OpenC3Authentication.new()
        else
          return nil
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end

    # Create a JsonDRbObject connection to the API server
    def initialize
      @json_drb = JsonDRbObject.new(
        url: generate_url(),
        timeout: generate_timeout(),
        authentication: generate_auth()
      )
    end

    # Ruby method which captures any method calls on this object. This allows
    # us to proxy the methods to the API server through the JsonDRbObject.
    def method_missing(method_name, *method_params, **kw_params)
      # Must call shutdown and disconnect on the JsonDRbObject itself
      # to avoid it being sent to the API
      kw_params[:scope] = $openc3_scope unless kw_params[:scope]
      case method_name
      when :shutdown
        @json_drb.shutdown
      when :request
        @json_drb.request(*method_params, **kw_params)
      else
        # If :disconnect is there delete it and return the value
        # If it is not there, delete returns nil
        disconnect = kw_params.delete(:disconnect)
        if $disconnect
          return disconnect if disconnect
          # The only commands allowed through in disconnect mode are read-only
          # Thus we allow the get, list, tlm and limits_enabled and subscribe methods
          if method_name =~ /\w*_get$|^get_\w*|\w*_list$|^list_\w*|^tlm|^limits_enabled$|^subscribe$/
            return @json_drb.method_missing(method_name, *method_params, **kw_params)
          else
            return nil
          end
        else
          @json_drb.method_missing(method_name, *method_params, **kw_params)
        end
      end
    end
  end

  # Provides a proxy to the Script Runner Api which communicates with the API server
  class ScriptServerProxy
    # pull openc3-cosmos-script-runner-api url from environment variables
    def generate_url
      schema = ENV['OPENC3_SCRIPT_API_SCHEMA'] || 'http'
      hostname = ENV['OPENC3_SCRIPT_API_HOSTNAME'] || (ENV['OPENC3_DEVEL'] ? '127.0.0.1' : 'openc3-cosmos-script-runner-api')
      port = ENV['OPENC3_SCRIPT_API_PORT'] || '2902'
      port = port.to_i
      return "#{schema}://#{hostname}:#{port}"
    end

    # pull openc3-cosmos-script-runner-api timeout from environment variables
    def generate_timeout
      timeout = ENV['OPENC3_SCRIPT_API_TIMEOUT'] || '5.0'
      return timeout.to_f
    end

    # generate the auth object
    def generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD']
          return OpenC3Authentication.new()
        else
          return nil
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end

    # Create a JsonDRbObject connection to the API server
    def initialize
      @json_api = JsonApiObject.new(
        url: generate_url(),
        timeout: generate_timeout(),
        authentication: generate_auth()
      )
    end

    def shutdown
      @json_api.shutdown
    end

    def request(*method_params, **kw_params)
      kw_params[:scope] = $openc3_scope unless kw_params[:scope]
      # If :disconnect is there delete it and return the value
      # If it is not there, delete returns nil
      disconnect = kw_params.delete(:disconnect)
      if $disconnect and disconnect
        # If they overrode the return value using the disconnect keyword then return that
        return disconnect
      else
        @json_api.request(*method_params, **kw_params)
      end
    end
  end
end
