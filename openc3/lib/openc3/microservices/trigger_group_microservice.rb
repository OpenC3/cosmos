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
require 'openc3/models/notification_model'
require 'openc3/models/trigger_model'
require 'openc3/topics/autonomic_topic'
require 'openc3/utilities/authentication'
require 'openc3/packets/json_packet'

require 'openc3/script'

module OpenC3
  class TriggerLoopError < TriggerError; end

  # Stored in the TriggerGroupShare this should be a thread safe
  # hash that triggers will be added, updated, and removed from
  class PacketBase
    def initialize(scope:)
      @scope = scope
      @mutex = Mutex.new
      @packets = Hash.new
    end

    def packet(target:, packet:)
      topic = "#{@scope}__DECOM__{#{target}}__#{packet}"
      @mutex.synchronize do
        return nil unless @packets[topic]
        # Deep copy the packet so it doesn't change under us
        return Marshal.load( Marshal.dump(@packets[topic][-1]) )
      end
    end

    def previous_packet(target:, packet:)
      topic = "#{@scope}__DECOM__{#{target}}__#{packet}"
      @mutex.synchronize do
        return nil unless @packets[topic] and @packets[topic].length == 2
        # Deep copy the packet so it doesn't change under us
        return Marshal.load( Marshal.dump(@packets[topic][0]) )
      end
    end

    def add(topic:, packet:)
      @mutex.synchronize do
        @packets[topic] ||= []
        if @packets[topic].length == 2
          @packets[topic].shift
        end
        @packets[topic].push(packet)
      end
    end

    def remove(topic:)
      @mutex.synchronize do
        @packets.delete(topic)
      end
    end
  end

  # Stored in the TriggerGroupShare this should be a thread safe
  # hash that triggers will be added, updated, and removed from.
  class TriggerBase
    attr_reader :autonomic_topic, :triggers

    def initialize(scope:)
      @scope = scope
      @autonomic_topic = "#{@scope}__openc3_autonomic".freeze
      @triggers_mutex = Mutex.new
      @triggers = Hash.new
      @lookup_mutex = Mutex.new
      @lookup = Hash.new
    end

    # Get triggers to evaluate based on the topic. If the
    # topic is equal to the autonomic topic it will
    # return only triggers with roots
    def get_triggers(topic:)
      if @autonomic_topic == topic
        return triggers_with_roots()
      else
        return triggers_from(topic: topic)
      end
    end

    # update trigger state after evaluated
    # -1 (the value is considered an error used to disable the trigger)
    #  0 (the value is considered as a false value)
    #  1 (the value is considered as a true value)
    def update_state(name:, value:)
      @triggers_mutex.synchronize do
        data = @triggers[name]
        return unless data
        trigger = TriggerModel.from_json(data, name: data['name'], scope: data['scope'])
        if value == -1 && trigger.enabled
          trigger.disable()
          trigger.update()
        elsif value == 1 && trigger.state == false
          trigger.state = true
        elsif value == 0 && trigger.state == true
          trigger.state = false
        end
        @triggers[name] = trigger.as_json(:allow_nan => true)
      end
    end

    # returns a Hash of ALL enabled Trigger objects
    def enabled_triggers
      val = nil
      @triggers_mutex.synchronize do
        val = Marshal.load( Marshal.dump(@triggers) )
      end
      ret = Hash.new
      val.each do | name, data |
        trigger = TriggerModel.from_json(data, name: data['name'], scope: data['scope'])
        ret[name] = trigger if trigger.enabled
      end
      return ret
    end

    # returns an Array of enabled Trigger objects that have roots to other triggers
    def triggers_with_roots
      val = nil
      @triggers_mutex.synchronize do
        val = Marshal.load( Marshal.dump(@triggers) )
      end
      ret = []
      val.each do | _name, data |
        trigger = TriggerModel.from_json(data, name: data['name'], scope: data['scope'])
        ret << trigger if trigger.enabled && ! trigger.roots.empty?
      end
      return ret
    end

    # returns an Array of enabled Trigger objects that use a topic
    def triggers_from(topic:)
      val = nil
      @lookup_mutex.synchronize do
        val = Marshal.load( Marshal.dump(@lookup[topic]) )
      end
      return [] if val.nil?
      ret = []
      @triggers_mutex.synchronize do
        val.each do | trigger_name |
          data = Marshal.load( Marshal.dump(@triggers[trigger_name]) )
          trigger = TriggerModel.from_json(data, name: data['name'], scope: data['scope'])
          ret << trigger if trigger.enabled
        end
      end
      return ret
    end

    # get all topics group is working with
    def topics
      @lookup_mutex.synchronize do
        return Marshal.load( Marshal.dump(@lookup.keys()) )
      end
    end

    # Rebuild the database lookup of all triggers in the group
    def rebuild(triggers:)
      @triggers_mutex.synchronize do
        @triggers = Marshal.load( Marshal.dump(triggers) )
      end
      @lookup_mutex.synchronize do
        @lookup = { @autonomic_topic => [] }
        triggers.each do | _name, data |
          trigger = TriggerModel.from_json(data, name: data['name'], scope: data['scope'])
          trigger.generate_topics.each do | topic |
            @lookup[topic] ||= []
            @lookup[topic] << trigger.name
          end
        end
      end
    end

    # Add a trigger from TriggerBase, must only be called once per trigger
    def add(trigger:)
      @triggers_mutex.synchronize do
        @triggers[trigger['name']] = Marshal.load( Marshal.dump(trigger) )
      end
      trigger = TriggerModel.from_json(trigger, name: trigger['name'], scope: trigger['scope'])
      @lookup_mutex.synchronize do
        trigger.generate_topics.each do | topic |
          @lookup[topic] ||= []
          @lookup[topic] << trigger.name
        end
      end
    end

    # update a trigger from TriggerBase
    def update(trigger:)
      @triggers_mutex.synchronize do
        model = TriggerModel.from_json(trigger, name: trigger['name'], scope: trigger['scope'])
        model.update()
        @triggers[trigger['name']] = model.as_json(:allow_nan => true)
      end
    end

    # remove a trigger from TriggerBase
    def remove(trigger:)
      topics = []
      @triggers_mutex.synchronize do
        @triggers.delete(trigger['name'])
        model = TriggerModel.from_json(trigger, name: trigger['name'], scope: trigger['scope'])
        topics = model.generate_topics()
        TriggerModel.delete(name: trigger['name'], group: trigger['group'], scope: trigger['scope'])
      end
      @lookup_mutex.synchronize do
        topics.each do | topic |
          unless @lookup[topic].nil?
            @lookup[topic].delete(trigger['name'])
            @lookup.delete(topic) if @lookup[topic].empty?
          end
        end
      end
    end
  end

  # Shared between the monitor thread and the manager thread to
  # share the triggers. This should remain a thread
  # safe implementation.
  class TriggerGroupShare
    attr_reader :trigger_base, :packet_base

    def initialize(scope:)
      @scope = scope
      @trigger_base = TriggerBase.new(scope: scope)
      @packet_base = PacketBase.new(scope: scope)
    end
  end

  # The TriggerGroupWorker is a very simple thread pool worker. Once
  # the trigger manager has pushed a packet to the queue one of
  # these workers will evaluate the triggers for that packet.
  class TriggerGroupWorker
    TYPE = 'type'.freeze
    ITEM_TARGET = 'target'.freeze
    ITEM_PACKET = 'packet'.freeze
    ITEM_TYPE = 'item'.freeze
    ITEM_VALUE_TYPE = 'valueType'.freeze
    FLOAT_TYPE = 'float'.freeze
    STRING_TYPE = 'string'.freeze
    REGEX_TYPE = 'regex'.freeze
    LIMIT_TYPE = 'limit'.freeze
    TRIGGER_TYPE = 'trigger'.freeze

    attr_reader :name, :scope, :target, :packet, :group

    def initialize(name:, logger:, scope:, group:, queue:, share:, ident:)
      @name = name
      @logger = logger
      @scope = scope
      @group = group
      @queue = queue
      @share = share
      @ident = ident
    end

    def notify(name:, severity:, message:)
      data = {}
      # All AutonomicTopic notifications must have 'name' and 'updated_at' in the data
      data['name'] = name
      data['updated_at'] = Time.now.to_nsec_from_epoch
      data['severity'] = severity
      data['message'] = message
      notification = {
        'kind' => 'error',
        'type' => 'trigger',
        'data' => JSON.generate(data),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)
      @logger.public_send(severity.intern, message)
    end

    def run
      @logger.info "TriggerGroupWorker-#{@ident} running"
      loop do
        topic = @queue.pop
        break if topic.nil?
        begin
          evaluate_data_packet(topic: topic)
        rescue StandardError => e
          @logger.error "TriggerGroupWorker-#{@ident} failed to evaluate data packet from topic: #{topic}\n#{e.formatted}"
        end
      end
      @logger.info "TriggerGroupWorker-#{@ident} exiting"
    end

    # Each packet will be evaluated to all triggers and use the result to send
    # the results back to the topic to be used by the reaction microservice.
    def evaluate_data_packet(topic:)
      visited = Hash.new
      @logger.debug "TriggerGroupWorker-#{@ident} topic: #{topic}"
      @share.trigger_base.get_triggers(topic: topic).each do |trigger|
        @logger.debug "TriggerGroupWorker-#{@ident} eval head: #{trigger}"
        value = evaluate_trigger(
          head: trigger,
          trigger: trigger,
          visited: visited,
          triggers: @share.trigger_base.enabled_triggers
        )
        @logger.debug "TriggerGroupWorker-#{@ident} trigger: #{trigger} value: #{value}"
        # value MUST be -1, 0, or 1
        @share.trigger_base.update_state(name: trigger.name, value: value)
      end
    end

    # extract the value outlined in the operand to get the packet item limit
    # IF operand limit does not include _LOW or _HIGH this will match the
    # COLOR and return COLOR_LOW || COLOR_HIGH
    # operand item: GREEN_LOW == other operand limit: GREEN
    def get_packet_limit(operand:, other:)
      packet = @share.packet_base.packet(
        target: operand[ITEM_TARGET],
        packet: operand[ITEM_PACKET]
      )
      return nil if packet.nil?
      _, limit = packet.read_with_limits_state(operand[ITEM_TYPE], operand[ITEM_VALUE_TYPE].intern)
      return limit
    end

    # extract the value outlined in the operand to get the packet item value
    # IF raw in operand it will pull the raw value over the converted
    def get_packet_value(operand:, previous:)
      if previous
        packet = @share.packet_base.previous_packet(
          target: operand[ITEM_TARGET],
          packet: operand[ITEM_PACKET]
        )
        # Previous might not be populated ... that's ok just return nil
        return nil unless packet
      else
        packet = @share.packet_base.packet(
          target: operand[ITEM_TARGET],
          packet: operand[ITEM_PACKET]
        )
      end
      # This shouldn't happen because the frontend provides valid items but good to check
      # The raise is ultimately rescued inside evaluate_trigger when operand_value is called
      raise "Packet #{operand[ITEM_TARGET]} #{operand[ITEM_PACKET]} not found" if packet.nil?
      value = packet.read(operand[ITEM_TYPE], operand[ITEM_VALUE_TYPE].intern)
      raise "Item #{operand[ITEM_TARGET]} #{operand[ITEM_PACKET]} #{operand[ITEM_TYPE]} not found" if value.nil?
      value
    end

    # extract the value of the operand from the packet
    def operand_value(operand:, other:, visited:, previous: false)
      if operand[TYPE] == ITEM_TYPE && other && other[TYPE] == LIMIT_TYPE
        return get_packet_limit(operand: operand, other: other)
      elsif operand[TYPE] == ITEM_TYPE
        return get_packet_value(operand: operand, previous: previous)
      elsif operand[TYPE] == TRIGGER_TYPE
        return visited["#{operand[TRIGGER_TYPE]}__R"] == 1
      elsif operand[TYPE] == FLOAT_TYPE
        return operand[operand[TYPE]].to_f
      elsif operand[TYPE] == STRING_TYPE
        return operand[operand[TYPE]].to_s
      elsif operand[TYPE] == REGEX_TYPE
        # This can potentially throw an exception on badly formatted Regexp
        return Regexp.new(operand[operand[TYPE]])
      elsif operand[TYPE] == LIMIT_TYPE
        return operand[operand[TYPE]]
      else
        # This is a logic error ... should never get here
        raise "Unknown operand type: #{operand}"
      end
    end

    # the base evaluate method used by evaluate_trigger
    #   -1 (the value is considered an error used to disable the trigger)
    #    0 (the value is considered as a false value)
    #    1 (the value is considered as a true value)
    #
    def evaluate(name:, left:, operator:, right:)
      @logger.debug "TriggerGroupWorker-#{@ident} evaluate: (#{left}(#{left.class}) #{operator} #{right}(#{right.class}))"
      begin
        case operator
        when '>'
          return left > right ? 1 : 0
        when '<'
          return left < right ? 1 : 0
        when '>='
          return left >= right ? 1 : 0
        when '<='
          return left <= right ? 1 : 0
        when '!=', 'CHANGES'
          return left != right ? 1 : 0
        when '==', 'DOES NOT CHANGE'
          return left == right ? 1 : 0
        when '!~'
          return left !~ right ? 1 : 0
        when '=~'
          return left =~ right ? 1 : 0
        when 'AND'
          return left && right ? 1 : 0
        when 'OR'
          return left || right ? 1 : 0
        end
      rescue ArgumentError => error
        message = "invalid evaluate: (#{left} #{operator} #{right})"
        notify(name: name, severity: 'error', message: message)
        return -1
      end
    end

    # This could be confusing... So this is a recursive method for the
    # TriggerGroupWorkers to call. It will use the trigger name and append a
    # __P for path or __R for result. The Path is a Hash that contains
    # a key for each node traveled to get results. When the result has
    # been found it will be stored in the result key __R in the visited Hash
    # and eval_trigger will return a number.
    #   -1 (the value is considered an error used to disable the trigger)
    #    0 (the value is considered as a false value)
    #    1 (the value is considered as a true value)
    #
    # IF an operand is evaluated as nil it will log an error and return -1
    # IF a loop is detected it will log an error and return -1
    def evaluate_trigger(head:, trigger:, visited:, triggers:)
      if visited["#{trigger.name}__R"]
        return visited["#{trigger.name}__R"]
      end
      if visited["#{trigger.name}__P"].nil?
        visited["#{trigger.name}__P"] = Hash.new
      end
      if visited["#{head.name}__P"][trigger.name]
        # Not sure if this is posible as on create it validates that the dependents are already created
        message = "loop detected from #{head.name} -> #{trigger.name} path: #{visited["#{head.name}__P"]}"
        notify(name: trigger.name, severity: 'error', message: error.message)
        return visited["#{trigger.name}__R"] = -1
      end
      trigger.roots.each do | root_trigger_name |
        next if visited["#{root_trigger_name}__R"]
        root_trigger = triggers[root_trigger_name]
        if head.name == root_trigger.name
          message = "loop detected from #{head.name} -> #{root_trigger_name} path: #{visited["#{head.name}__P"]}"
          notify(name: trigger.name, severity: 'error', message: error.message)
          return visited["#{trigger.name}__R"] = -1
        end
        result = evaluate_trigger(
          head: head,
          trigger: root_trigger,
          visited: visited,
          triggers: triggers
        )
        @logger.debug "TriggerGroupWorker-#{@ident} #{root_trigger.name} result: #{result}"
        visited["#{root_trigger.name}__R"] = visited["#{head.name}__P"][root_trigger.name] = result
      end
      begin
        left = operand_value(operand: trigger.left, other: trigger.right, visited: visited)
        if trigger.operator.include?('CHANGE')
          right = operand_value(operand: trigger.left, other: trigger.right, visited: visited, previous: true)
        else
          right = operand_value(operand: trigger.right, other: trigger.left, visited: visited)
        end
      rescue => error
        # This will primarily happen when the user inputs a bad Regexp
        notify(name: trigger.name, severity: 'error', message: error.message)
        return visited["#{trigger.name}__R"] = -1
      end
      # Convert the standard '==' and '!=' into Ruby Regexp operators
      operator = trigger.operator
      if right and right.is_a? Regexp
        operator = '=~' if operator == '=='
        operator = '!~' if operator == '!='
      end
      if left.nil? || right.nil?
        return visited["#{trigger.name}__R"] = 0
      end
      result = evaluate(name: trigger.name,left: left, operator: operator, right: right)
      return visited["#{trigger.name}__R"] = result
    end
  end

  # The trigger manager starts a thread pool and subscribes
  # to the telemtry decom topic. It adds the "packet" to the thread pool queue
  # and the thread will evaluate the "trigger".
  class TriggerGroupManager
    attr_reader :name, :scope, :share, :group, :topics, :thread_pool

    def initialize(name:, logger:, scope:, group:, share:)
      @name = name
      @logger = logger
      @scope = scope
      @group = group
      @share = share
      @worker_count = 3
      @queue = Queue.new
      @read_topic = true
      @topics = []
      @thread_pool = nil
      @cancel_thread = false
    end

    def generate_thread_pool()
      thread_pool = []
      @worker_count.times do | i |
        worker = TriggerGroupWorker.new(
          name: @name,
          logger: @logger,
          scope: @scope,
          group: @group,
          queue: @queue,
          share: @share,
          ident: i,
        )
        thread_pool << Thread.new { worker.run }
      end
      return thread_pool
    end

    def run
      @logger.info "TriggerGroupManager running"
      @thread_pool = generate_thread_pool()
      loop do
        begin
          update_topics()
        rescue StandardError => e
          @logger.error "TriggerGroupManager failed to update topics.\n#{e.formatted}"
        end
        break if @cancel_thread
        block_for_updates()
        break if @cancel_thread
      end
      @logger.info "TriggerGroupManager exiting"
    end

    def update_topics
      past_topics = @topics
      @topics = @share.trigger_base.topics()
      @logger.debug "TriggerGroupManager past_topics: #{past_topics} topics: #{@topics}"
      (past_topics - @topics).each do | removed_topic |
        @share.packet_base.remove(topic: removed_topic)
      end
    end

    def block_for_updates
      @read_topic = true
      while @read_topic
        begin
          Topic.read_topics(@topics) do |topic, _msg_id, msg_hash, _redis|
            @logger.debug "TriggerGroupManager block_for_updates: #{topic} #{msg_hash.to_s}"
            if topic != @share.trigger_base.autonomic_topic
              packet = JsonPacket.new(:TLM, msg_hash['target_name'], msg_hash['packet_name'], msg_hash['time'].to_i, false, msg_hash["json_data"])
              @share.packet_base.add(topic: topic, packet: packet)
            end
            @queue << "#{topic}"
          end
        rescue StandardError => e
          @logger.error "TriggerGroupManager failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def refresh
      @read_topic = false
    end

    def shutdown
      @read_topic = false
      @cancel_thread = true
      @worker_count.times do | i |
        @queue << nil
      end
    end
  end

  # The trigger microservice starts a manager then gets the activities
  # from the sorted set in redis and updates the schedule for the
  # manager. Timeline will then wait for an update on the timeline
  # stream this will trigger an update again to the schedule.
  class TriggerGroupMicroservice < Microservice
    attr_reader :name, :scope, :share, :group, :manager, :manager_thread
    # This lookup is mapping all the different trigger notifications
    # which are primarily sent by notify in TriggerModel
    TOPIC_LOOKUP = {
      'error' => :no_op, # Sent by TriggerGroupWorker
      'created' => :created_trigger_event,
      'updated' => :rebuild_trigger_event,
      'deleted' => :deleted_trigger_event,
      'enabled' => :updated_trigger_event,
      'disabled' => :updated_trigger_event,
      'true' => :no_op, # Sent by TriggerGroupWorker
      'false' => :no_op, # Sent by TriggerGroupWorker
    }

    def initialize(*args)
      super(*args)
      # The name is passed in via the trigger_group_model as "#{scope}__TRIGGER_GROUP__#{name}"
      @group = @name.split('__')[2]
      @share = TriggerGroupShare.new(scope: @scope)
      @manager = TriggerGroupManager.new(name: @name, logger: @logger, scope: @scope, group: @group, share: @share)
      @manager_thread = nil
      @read_topic = true
    end

    def run
      @logger.info "TriggerGroupMicroservice running"
      @manager_thread = Thread.new { @manager.run }
      loop do
        triggers = TriggerModel.all(scope: @scope, group: @group)
        @share.trigger_base.rebuild(triggers: triggers)
        @manager.refresh() # Everytime we do a full base update we refesh the manager
        break if @cancel_thread
        block_for_updates()
        break if @cancel_thread
      end
      @logger.info "TriggerGroupMicroservice exiting"
    end

    def block_for_updates
      @read_topic = true
      while @read_topic && !@cancel_thread
        begin
          AutonomicTopic.read_topics(@topics) do |_topic, _msg_id, msg_hash, _redis|
            break if @cancel_thread
            @logger.debug "TriggerGroupMicroservice block_for_updates: #{msg_hash.to_s}"
            # Process trigger notifications created by TriggerModel notify
            if msg_hash['type'] == 'trigger'
              data = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
              public_send(TOPIC_LOOKUP[msg_hash['kind']], data)
            end
          end
        rescue StandardError => e
          @logger.error "TriggerGroupMicroservice failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def no_op(data)
      @logger.debug "TriggerGroupMicroservice web socket event: #{data}"
    end

    # Add the trigger to the share.
    def created_trigger_event(data)
      @logger.debug "TriggerGroupMicroservice created_trigger_event #{data}"
      if data['group'] == @group
        @share.trigger_base.add(trigger: data)
        @manager.refresh()
      end
    end

    def updated_trigger_event(data)
      @logger.debug "TriggerGroupMicroservice updated_trigger_event #{data}"
      if data['group'] == @group
        @share.trigger_base.update(trigger: data)
      end
    end

    # When a trigger is updated it could change items which modifies topics and
    # potentially adds or removes topics so refresh everything just to be safe
    def rebuild_trigger_event(data)
      @logger.debug "TriggerGroupMicroservice rebuild_trigger_event #{data}"
      if data['group'] == @group
        @share.trigger_base.update(trigger: data)
        @read_topic = false
      end
    end

    # Remove the trigger from the share.
    def deleted_trigger_event(data)
      @logger.debug "TriggerGroupMicroservice deleted_trigger_event #{data}"
      if data['group'] == @group
        @share.trigger_base.remove(trigger: data)
        @manager.refresh()
      end
    end

    def shutdown
      @read_topic = false
      @manager.shutdown()
      super
    end
  end
end

OpenC3::TriggerGroupMicroservice.run if __FILE__ == $0
