# encoding: ascii-8bit

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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'
require 'openc3/models/microservice_model'
require 'openc3/topics/queue_topic'
require 'openc3/utilities/logger'

module OpenC3
  class QueueError < StandardError; end

  class QueueModel < Model
    PRIMARY_KEY = 'openc3__queue'.freeze

    @@class_mutex = Mutex.new

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
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

    # Convert cmd_params hash to JSON-safe format
    # Base64 encodes binary strings that can't be safely represented in UTF-8
    # @param params [Hash] Hash of command parameters
    # @return [Hash] Hash with binary strings converted to base64-encoded format
    def self.convert_params_to_json_safe(params)
      safe_params = {}
      (params || {}).each do |key, value|
        if value.is_a?(String)
          # Try to convert to UTF-8. If it fails, it's binary data that needs base64 encoding
          begin
            utf8_value = value.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            # If the conversion changed the string, it contained invalid UTF-8, so base64 encode it
            if utf8_value != value || !value.valid_encoding?
              safe_params[key] = { '__base64__' => true, 'data' => [value].pack('m0') }
            else
              safe_params[key] = value
            end
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            # Failed to convert - definitely binary, base64 encode it
            safe_params[key] = { '__base64__' => true, 'data' => [value].pack('m0') }
          end
        elsif value.respond_to?(:as_json)
          safe_params[key] = value.as_json
        else
          safe_params[key] = value
        end
      end
      safe_params
    end

    def self.queue_command(name, command: nil, target_name: nil, cmd_name: nil, cmd_params: nil, username:, scope:)
      model = get_model(name: name, scope: scope)
      raise QueueError, "Queue '#{name}' not found in scope '#{scope}'" unless model

      if model.state != 'DISABLE'
        result = Store.zrevrange("#{scope}:#{name}", 0, 0, with_scores: true)
        if result.empty?
          id = 1.0
        else
          id = result[0][1].to_f + 1
        end

        # Build command data with support for both formats
        command_data = { username: username, timestamp: Time.now.to_nsec_from_epoch }
        if target_name && cmd_name
          # New format: store target_name, cmd_name, and cmd_params separately
          command_data[:target_name] = target_name
          command_data[:cmd_name] = cmd_name
          command_data[:cmd_params] = convert_params_to_json_safe(cmd_params)
        elsif command
          # Legacy format: store command string for backwards compatibility
          command_data[:value] = command
        else
          raise QueueError, "Must provide either command string or target_name/cmd_name parameters"
        end

        Store.zadd("#{scope}:#{name}", id, command_data.to_json)
        model.notify(kind: 'command')
      else
        error_msg = command || "#{target_name} #{cmd_name}"
        raise QueueError, "Queue '#{name}' is disabled. Command '#{error_msg}' not queued."
      end
    end

    attr_accessor :name, :state

    def initialize(name:, scope:, state: 'HOLD', updated_at: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, scope: scope)
      @microservice_name = "#{scope}__QUEUE__#{name}"
      if %w(HOLD RELEASE DISABLE).include?(state)
        @state = state
      else
        @state = 'HOLD'
      end
    end

    def create(update: false, force: false, queued: false)
      super(update: update, force: force, queued: queued)
      if update
        notify(kind: 'updated')
      else
        deploy()
        notify(kind: 'created')
      end
    end

    # @return [Hash] generated from the QueueModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'state' => @state,
        'updated_at' => @updated_at
      }
    end

    # @return [] update the redis stream / queue topic that something has changed
    def notify(kind:)
      notification = {
        'kind' => kind,
        'data' => JSON.generate(as_json, allow_nan: true),
      }
      QueueTopic.write_notification(notification, scope: @scope)
    end

    def insert_command(id, command_data)
      if @state == 'DISABLE'
        raise QueueError, "Queue '#{@name}' is disabled. Command '#{command_data['value']}' not queued."
      end

      unless id
        result = Store.zrevrange("#{@scope}:#{@name}", 0, 0, with_scores: true)
        if result.empty?
          id = 1.0
        else
          id = result[0][1].to_f + 1
        end
      end

      # Convert cmd_params values to JSON-safe format if present
      if command_data['cmd_params'] || command_data[:cmd_params]
        safe_data = command_data.dup
        params_key = command_data.key?('cmd_params') ? 'cmd_params' : :cmd_params
        safe_data[params_key] = self.class.convert_params_to_json_safe(command_data[params_key])
        Store.zadd("#{@scope}:#{@name}", id, safe_data.to_json)
      else
        Store.zadd("#{@scope}:#{@name}", id, command_data.to_json)
      end
      notify(kind: 'command')
    end

    def update_command(id:, command:, username:)
      if @state == 'DISABLE'
        raise QueueError, "Queue '#{@name}' is disabled. Command at id #{id} not updated."
      end

      # Check if command exists at the given id
      existing = Store.zrangebyscore("#{@scope}:#{@name}", id, id)
      if existing.empty?
        raise QueueError, "No command found at id #{id} in queue '#{@name}'"
      end

      # Remove the existing command and add the new one at the same id
      Store.zremrangebyscore("#{@scope}:#{@name}", id, id)
      command_data = { username: username, value: command, timestamp: Time.now.to_nsec_from_epoch }
      Store.zadd("#{@scope}:#{@name}", id, command_data.to_json)
      notify(kind: 'command')
    end

    def remove_command(id = nil)
      if @state == 'DISABLE'
        raise QueueError, "Queue '#{@name}' is disabled. Command not removed."
      end

      if id
        # Remove specific id
        result = Store.zrangebyscore("#{@scope}:#{@name}", id, id)
        if result.empty?
          return nil
        else
          Store.zremrangebyscore("#{@scope}:#{@name}", id, id)
          command_data = JSON.parse(result[0])
          command_data['id'] = id.to_f
          notify(kind: 'command')
          return command_data
        end
      else
        # Remove first element (lowest score)
        result = Store.zrange("#{@scope}:#{@name}", 0, 0, with_scores: true)
        if result.empty?
          return nil
        else
          score = result[0][1]
          Store.zremrangebyscore("#{@scope}:#{@name}", score, score)
          command_data = JSON.parse(result[0][0])
          command_data['id'] = score.to_f
          notify(kind: 'command')
          return command_data
        end
      end
    end

    def list
      return Store.zrange("#{@scope}:#{@name}", 0, -1, with_scores: true).map do |item|
        result = JSON.parse(item[0])
        result['id'] = item[1].to_f
        result
      end
    end

    def create_microservice(topics:)
      # queue Microservice
      microservice = MicroserviceModel.new(
        name: @microservice_name,
        folder_name: nil,
        cmd: ['ruby', 'queue_microservice.rb', @microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["QUEUE_STATE", @state],
        ],
        topics: topics,
        target_names: [],
        plugin: nil,
        scope: @scope
      )
      microservice.create
    end

    def deploy
      topics = ["#{@scope}__#{QueueTopic::PRIMARY_KEY}"]
      if MicroserviceModel.get_model(name: @microservice_name, scope: @scope).nil?
        create_microservice(topics: topics)
      end
    end

    def undeploy
      model = MicroserviceModel.get_model(name: @microservice_name, scope: @scope)
      if model
        # Let the frontend know that the microservice is shutting down
        # Custom event which matches the 'deployed' event in QueueMicroservice
        notification = {
          'kind' => 'undeployed',
          # name and updated_at fields are required for Event formatting
          'data' => JSON.generate({
            'name' => @microservice_name,
            'updated_at' => Time.now.to_nsec_from_epoch,
          }),
        }
        QueueTopic.write_notification(notification, scope: @scope)
        model.destroy
      end
    end

    # Delete the model from the Store
    def destroy
      undeploy()
      Store.zremrangebyrank("#{@scope}:#{@name}", 0, -1)
      super()
    end
  end
end