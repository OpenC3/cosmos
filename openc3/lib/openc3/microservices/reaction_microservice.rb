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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/microservices/microservice'
require 'openc3/models/reaction_model'
require 'openc3/models/trigger_model'
require 'openc3/topics/autonomic_topic'
require 'openc3/utilities/authentication'

require 'openc3/script'

module OpenC3
  # This should remain a thread safe implementation. This is the in memory
  # cache that should mirror the database. This will update two hash
  # variables and will track triggers to lookup what triggers link to what
  # reactions.
  class ReactionBase
    attr_reader :reactions

    def initialize(scope:)
      @scope = scope
      @reactions_mutex = Mutex.new
      @reactions = Hash.new
      @lookup_mutex = Mutex.new
      @lookup = Hash.new
    end

    # RETURNS an Array of actively snoozed reactions
    def get_snoozed
      data = nil
      @reactions_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@reactions) )
      end
      ret = Array.new
      return ret unless data
      data.each do |_name, r_hash|
        data = Marshal.load( Marshal.dump(r_hash) )
        reaction = ReactionModel.from_json(data, name: data['name'], scope: data['scope'])
        ret << reaction if reaction.enabled && reaction.snoozed_until
      end
      return ret
    end

    # RETURNS an Array of actively NOT snoozed reactions
    def get_reactions(trigger_name:)
      array_value = nil
      @lookup_mutex.synchronize do
        array_value = Marshal.load( Marshal.dump(@lookup[trigger_name]) )
      end
      ret = Array.new
      return ret unless array_value
      array_value.each do |name|
        @reactions_mutex.synchronize do
          data = Marshal.load( Marshal.dump(@reactions[name]) )
          reaction = ReactionModel.from_json(data, name: data['name'], scope: data['scope'])
          ret << reaction if reaction.enabled && reaction.snoozed_until.nil?
        end
      end
      return ret
    end

    # Update the memory database with a HASH of reactions from the external database
    def setup(reactions:)
      @reactions_mutex.synchronize do
        @reactions = Marshal.load( Marshal.dump(reactions) )
      end
      @lookup_mutex.synchronize do
        @lookup = Hash.new
        reactions.each do |reaction_name, reaction|
          reaction['triggers'].each do |trigger|
            trigger_name = trigger['name']
            if @lookup[trigger_name].nil?
              @lookup[trigger_name] = [reaction_name]
            else
              @lookup[trigger_name] << reaction_name
            end
          end
        end
      end
    end

    # Pulls the latest reaction name from the in memory database to see
    # if the reaction should be put to sleep.
    def sleep(name:)
      @reactions_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@reactions[name]) )
        return unless data
        reaction = ReactionModel.from_json(data, name: data['name'], scope: data['scope'])
        if reaction.snoozed_until.nil? || Time.now.to_i >= reaction.snoozed_until
          reaction.sleep()
        end
        @reactions[name] = reaction.as_json(:allow_nan => true)
      end
    end

    # Pulls the latest reaction name from the in memory database to see
    # if the reaction should be awaken.
    def wake(name:)
      @reactions_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@reactions[name]) )
        return unless data
        reaction = ReactionModel.from_json(data, name: data['name'], scope: data['scope'])
        reaction.awaken()
        @reactions[name] = reaction.as_json(:allow_nan => true)
      end
    end

    # Add a reaction to the in memory database
    def add(reaction:)
      reaction_name = reaction['name']
      @reactions_mutex.synchronize do
        @reactions[reaction_name] = reaction
      end
      reaction['triggers'].each do |trigger|
        trigger_name = trigger['name']
        @lookup_mutex.synchronize do
          if @lookup[trigger_name].nil?
            @lookup[trigger_name] = [reaction_name]
          else
            @lookup[trigger_name] << reaction_name
          end
        end
      end
    end

    # Updates a reaction to the in memory database. This current does not
    # update the lookup Hash for the triggers.
    def update(reaction:)
      @reactions_mutex.synchronize do
        model = ReactionModel.from_json(reaction, name: reaction['name'], scope: reaction['scope'])
        model.update()
        @reactions[reaction['name']] = model.as_json(:allow_nan => true)
      end
    end

    # Removes a reaction to the in memory database.
    def remove(reaction:)
      @reactions_mutex.synchronize do
        @reactions.delete(reaction['name'])
        ReactionModel.delete(name: reaction['name'], scope: reaction['scope'])
      end
      reaction['triggers'].each do |trigger|
        trigger_name = trigger['name']
        @lookup_mutex.synchronize do
          @lookup[trigger_name].delete(reaction['name'])
        end
      end
    end
  end

  # This should remain a thread safe implementation.
  class QueueBase
    attr_reader :queue

    def initialize(scope:)
      @queue = Queue.new
    end

    def enqueue(kind:, data:)
      @queue << [kind, data]
    end
  end

  # This should remain a thread safe implementation.
  class SnoozeBase
    def initialize(scope:)
      # store the round robin watch
      @watch_mutex = Mutex.new
      @watch_size = 25
      @watch_queue = Array.new(@watch_size)
      @watch_index = 0
    end

    def not_queued?(reaction:)
      key = "#{reaction.name}__#{reaction.snoozed_until}"
      @watch_mutex.synchronize do
        return false if @watch_queue.index(key)
        @watch_queue[@watch_index] = key
        @watch_index = @watch_index + 1 >= @watch_size ? 0 : @watch_index + 1
        return true
      end
    end
  end

  # Shared between the monitor thread and the manager thread to
  # share the resources.
  class ReactionShare
    attr_reader :reaction_base, :queue_base, :snooze_base

    def initialize(scope:)
      @reaction_base = ReactionBase.new(scope: scope)
      @queue_base = QueueBase.new(scope: scope)
      @snooze_base = SnoozeBase.new(scope: scope)
    end
  end

  # The Reaction worker is a very simple thread pool worker. Once the manager
  # queues a trigger to evaluate against the reactions. The worker will check
  # the reactions to see if it needs to fire any reactions.
  class ReactionWorker
    attr_reader :name, :scope, :share

    def initialize(name:, logger:, scope:, share:, ident:)
      @name = name
      @logger = logger
      @scope = scope
      @share = share
      @ident = ident
    end

    def get_token(username)
      if ENV['OPENC3_API_CLIENT'].nil?
        ENV['OPENC3_API_PASSWORD'] ||= ENV['OPENC3_SERVICE_PASSWORD']
        return OpenC3Authentication.new().token
      else
        # Check for offline access token
        model = nil
        model = OpenC3::OfflineAccessModel.get_model(name: username, scope: @scope) if username and username != ''
        if model and model.offline_access_token
          auth = OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
          return auth.get_token_from_refresh_token(model.offline_access_token)
        else
          return nil
        end
      end
    end

    def reaction(data:)
      return ReactionModel.from_json(data, name: data['name'], scope: data['scope'])
    end

    def run
      @logger.info "ReactionWorker-#{@ident} running"
      loop do
        begin
          kind, data = @share.queue_base.queue.pop
          break if kind.nil? || data.nil?
          case kind
          when 'reaction'
            run_reaction(reaction: reaction(data: data))
          when 'trigger'
            process_true_trigger(data: data)
          end
        rescue StandardError => e
          @logger.error "ReactionWorker-#{@ident} failed to evaluate kind: #{kind} data: #{data}\n#{e.formatted}"
        end
      end
      @logger.info "ReactionWorker-#{@ident} exiting"
    end

    def process_true_trigger(data:)
      @share.reaction_base.get_reactions(trigger_name: data['name']).each do |reaction|
        run_reaction(reaction: reaction)
      end
    end

    def run_reaction(reaction:)
      reaction.actions.each do |action|
        run_action(reaction: reaction, action: action)
      end
      @share.reaction_base.sleep(name: reaction.name)
    end

    def run_action(reaction:, action:)
      reaction.updated_at = Time.now.to_nsec_from_epoch
      reaction_json = reaction.as_json(:allow_nan => true)
      # Let the frontend know which action is being run
      # because we can combine commands and scripts with notifications
      reaction_json['action'] = action['type']
      notification = {
        'kind' => 'run',
        'type' => 'reaction',
        'data' => JSON.generate(reaction_json),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)

      case action['type']
      when 'notify'
        run_notify(reaction: reaction, action: action)
      when 'command'
        run_command(reaction: reaction, action: action)
      when 'script'
        run_script(reaction: reaction, action: action)
      end
    end

    def run_notify(reaction:, action:)
      message = "ReactionWorker-#{@ident} #{reaction.name} notify action complete, body: #{action['value']}"
      url = "/tools/autonomic/reactions"
      case action['severity'].to_s.upcase
      when 'FATAL'
        @logger.fatal(message, url: url, type: Logger::ALERT)
      when 'ERROR', 'CRITICAL'
        @logger.error(message, url: url, type: Logger::ALERT)
      when 'WARN', 'CAUTION', 'SERIOUS'
        @logger.warn(message, url: url, type: Logger::NOTIFICATION)
      when 'INFO', 'NORMAL', 'STANDBY', 'OFF'
        @logger.info(message, url: url, type: Logger::NOTIFICATION)
      when 'DEBUG'
        level = @logger.level
        begin
          @logger.level = Logger::DEBUG
          @logger.debug(message, url: url, type: Logger::NOTIFICATION)
        ensure
          @logger.level = level
        end
      else
        raise "Unknown severity: #{action['severity']}"
      end
    end

    def run_command(reaction:, action:)
      begin
        username = reaction.username
        token = get_token(username)
        raise "No token available for username: #{username}" unless token
        cmd_no_hazardous_check(action['value'], scope: @scope, token: token)
        @logger.info "ReactionWorker-#{@ident} #{reaction.name} command action complete, command: #{action['value']}"
      rescue StandardError => e
        @logger.error "ReactionWorker-#{@ident} #{reaction.name} command action failed, #{action}\n#{e.message}"
      end
    end

    def run_script(reaction:, action:)
      begin
        username = reaction.username
        token = get_token(username)
        raise "No token available for username: #{username}" unless token
        request = Net::HTTP::Post.new(
          "/script-api/scripts/#{action['value']}/run?scope=#{@scope}",
          'Content-Type' => 'application/json',
          'Authorization' => token
        )
        request.body = JSON.generate({
          'scope' => @scope,
          'environment' => action['environment'],
          'reaction' => reaction.name,
          'id' => Time.now.to_i
        })
        hostname = ENV['OPENC3_SCRIPT_HOSTNAME'] || 'openc3-cosmos-script-runner-api'
        response = Net::HTTP.new(hostname, 2902).request(request)
        raise "failed to call #{hostname}, for script: #{action['value']}, response code: #{response.code}" if response.code != '200'

        @logger.info "ReactionWorker-#{@ident} #{reaction.name} script action complete, #{action['value']} => #{response.body}"
      rescue StandardError => e
        @logger.error "ReactionWorker-#{@ident} #{reaction.name} script action failed, #{action}\n#{e.message}"
      end
    end
  end

  # The reaction snooze manager starts a thread pool and keeps track of when a
  # reaction is activated and to evaluate triggers when the snooze is complete.
  class ReactionSnoozeManager
    attr_reader :name, :scope, :share, :thread_pool

    def initialize(name:, logger:, scope:, share:)
      @name = name
      @logger = logger
      @scope = scope
      @share = share
      @worker_count = 3
      @thread_pool = nil
      @cancel_thread = false
    end

    def generate_thread_pool()
      thread_pool = []
      @worker_count.times do |i|
        worker = ReactionWorker.new(name: @name, logger: @logger, scope: @scope, share: @share, ident: i)
        thread_pool << Thread.new { worker.run }
      end
      return thread_pool
    end

    def run
      @logger.info "ReactionSnoozeManager running"
      @thread_pool = generate_thread_pool()
      loop do
        begin
          current_time = Time.now.to_i
          manage_snoozed_reactions(current_time: current_time)
        rescue StandardError => e
          @logger.error "ReactionSnoozeManager failed to snooze reactions.\n#{e.formatted}"
        end
        break if @cancel_thread
        sleep(1)
        break if @cancel_thread
      end
      @logger.info "ReactionSnoozeManager exiting"
    end

    def active_triggers(reaction:)
      reaction.triggers.each do |trigger|
        t = TriggerModel.get(name: trigger['name'], group: trigger['group'], scope: @scope)
        return true if t && t.state
      end
      return false
    end

    def manage_snoozed_reactions(current_time:)
      @share.reaction_base.get_snoozed.each do |reaction|
        time_difference = reaction.snoozed_until - current_time
        if time_difference <= 0 && @share.snooze_base.not_queued?(reaction: reaction)
          # LEVEL triggers mean we run if the trigger is active
          if reaction.triggerLevel == 'LEVEL' and active_triggers(reaction: reaction)
            @share.queue_base.enqueue(kind: 'reaction', data: reaction.as_json(:allow_nan => true))
          else
            @share.reaction_base.wake(name: reaction.name)
          end
        end
      end
    end

    def shutdown
      @cancel_thread = true
      @worker_count.times do |_i|
        @share.queue_base.enqueue(kind: nil, data: nil)
      end
    end
  end

  # The reaction microservice starts a manager then gets the
  # reactions and triggers from redis. It then monitors the
  # AutonomicTopic for changes.
  class ReactionMicroservice < Microservice
    attr_reader :name, :scope, :share, :manager, :manager_thread
    TOPIC_LOOKUP = {
      'group' => {
        'created' => :no_op,
        'updated' => :no_op,
        'deleted' => :no_op,
      },
      'trigger' => {
        'error' => :no_op,
        'created' => :no_op,
        'updated' => :no_op,
        'deleted' => :no_op,
        'enabled' => :no_op,
        'disabled' => :no_op,
        'true' => :trigger_true_event,
        'false' => :no_op,
      },
      'reaction' => {
        'run' => :no_op,
        'deployed' => :no_op,
        'undeployed' => :no_op,
        'created' => :reaction_created_event,
        'updated' => :reaction_updated_event,
        'deleted' => :reaction_deleted_event,
        'enabled' => :reaction_enabled_event,
        'disabled' => :reaction_disabled_event,
        'snoozed' => :no_op,
        'awakened' => :no_op,
        'executed' => :reaction_execute_event,
      }
    }

    def initialize(*args)
      # The name is passed in via the reaction_model as "#{scope}__OPENC3__REACTION"
      super(*args)
      @share = ReactionShare.new(scope: @scope)
      @manager = ReactionSnoozeManager.new(name: @name, logger: @logger, scope: @scope, share: @share)
      @manager_thread = nil
      @read_topic = true
    end

    def run
      @logger.info "ReactionMicroservice running"
      # Let the frontend know that the microservice has been deployed and is running
      notification = {
        'kind' => 'deployed',
        'type' => 'reaction',
        # name and updated_at fields are required for Event formatting
        'data' => JSON.generate({
          'name' => @name,
          'updated_at' => Time.now.to_nsec_from_epoch,
        }),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)

      @manager_thread = Thread.new { @manager.run }
      loop do
        reactions = ReactionModel.all(scope: @scope)
        @share.reaction_base.setup(reactions: reactions)
        break if @cancel_thread
        block_for_updates()
        break if @cancel_thread
      end
      @logger.info "ReactionMicroservice exiting"
    end

    def block_for_updates
      @read_topic = true
      while @read_topic && !@cancel_thread
        begin
          AutonomicTopic.read_topics(@topics) do |_topic, _msg_id, msg_hash, _redis|
            @logger.debug "ReactionMicroservice block_for_updates: #{msg_hash.to_s}"
            public_send(TOPIC_LOOKUP[msg_hash['type']][msg_hash['kind']], msg_hash)
          end
        rescue StandardError => e
          @logger.error "ReactionMicroservice failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def no_op(data)
      @logger.debug "ReactionMicroservice web socket event: #{data}"
    end

    def reaction_updated_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction updated msg_hash: #{msg_hash}"
      reaction = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.reaction_base.update(reaction: reaction)
      @read_topic = false
    end

    def trigger_true_event(msg_hash)
      @logger.debug "ReactionMicroservice trigger true msg_hash: #{msg_hash}"
      @share.queue_base.enqueue(kind: 'trigger', data: JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true))
    end

    # Add the reaction to the shared data.
    def reaction_created_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction created msg_hash: #{msg_hash}"
      reaction = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.reaction_base.add(reaction: reaction)

      # If the reaction triggerLevel is LEVEL we have to check its triggers
      # on add because if the trigger is active it should run
      if reaction['triggerLevel'] == 'LEVEL'
        reaction['triggers'].each do |trigger_hash|
          trigger = TriggerModel.get(name: trigger_hash['name'], group: trigger_hash['group'], scope: reaction['scope'])
          if trigger && trigger.state
            @logger.info "ReactionMicroservice reaction #{reaction['name']} created. Since triggerLevel is 'LEVEL' it was run due to #{trigger.name}."
            @share.queue_base.enqueue(kind: 'reaction', data: reaction)
          end
        end
      end
    end

    # Update the reaction to the shared data.
    def reaction_enabled_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction enabled msg_hash: #{msg_hash}"
      reaction = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.reaction_base.update(reaction: reaction)

      # If the reaction triggerLevel is LEVEL we have to check its triggers
      # on add because if the trigger is active it should run
      if reaction['triggerLevel'] == 'LEVEL'
        reaction['triggers'].each do |trigger_hash|
          trigger = TriggerModel.get(name: trigger_hash['name'], group: trigger_hash['group'], scope: reaction['scope'])
          if trigger && trigger.state
            @logger.info "ReactionMicroservice reaction #{reaction['name']} enabled. Since triggerLevel is 'LEVEL' it was run due to #{trigger.name}."
            @share.queue_base.enqueue(kind: 'reaction', data: reaction)
          end
        end
      end
    end

    # Update the reaction to the shared data.
    def reaction_disabled_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction disabled msg_hash: #{msg_hash}"
      @share.reaction_base.update(reaction: JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true))
    end

    # Add the reaction to the shared data.
    def reaction_execute_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction execute msg_hash: #{msg_hash}"
      reaction = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.reaction_base.update(reaction: reaction)
      @share.queue_base.enqueue(kind: 'reaction', data: reaction)
    end

    # Remove the reaction from the shared data
    def reaction_deleted_event(msg_hash)
      @logger.debug "ReactionMicroservice reaction deleted msg_hash: #{msg_hash}"
      @share.reaction_base.remove(reaction: JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true))
    end

    def shutdown
      @read_topic = false
      @manager.shutdown()
      super
    end
  end
end

OpenC3::ReactionMicroservice.run if __FILE__ == $0
