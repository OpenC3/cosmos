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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'

module OpenC3
  class ScriptStatusModel < Model
    # Note: ScriptRunner only has permissions for keys that start with running-script
    RUNNING_PRIMARY_KEY = 'running-script'
    COMPLETED_PRIMARY_KEY = 'running-script-completed'

    def id
      return @name
    end
    attr_reader :state # spawning, init, running, paused, waiting, breakpoint, error, crashed, stopped, completed, completed_errors, killed
    attr_accessor :shard
    attr_accessor :filename
    attr_accessor :current_filename
    attr_accessor :line_no
    attr_accessor :start_line_no
    attr_accessor :end_line_no
    attr_accessor :username
    attr_accessor :user_full_name
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :disconnect
    attr_accessor :environment
    attr_accessor :suite_runner
    attr_accessor :errors
    attr_accessor :pid
    attr_accessor :log
    attr_accessor :report
    attr_accessor :script_engine

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:, type: "auto")
      if type == "running-only"
        running = super("#{RUNNING_PRIMARY_KEY}__#{scope}", name: name)
        return running
      end

      if type == "auto" or type == "running"
        # Check for running first
        running = super("#{RUNNING_PRIMARY_KEY}__#{scope}", name: name)
        return running if running
      end
      return super("#{COMPLETED_PRIMARY_KEY}__#{scope}", name: name)
    end

    def self.names(scope:, type: "running")
      if type == "running"
        return super("#{RUNNING_PRIMARY_KEY}__#{scope}")
      else
        return super("#{COMPLETED_PRIMARY_KEY}__#{scope}")
      end
    end

    def self.all(scope:, offset: 0, limit: 10, type: "running")
      if type == "running"
        keys = self.store.zrevrange("#{RUNNING_PRIMARY_KEY}__#{scope}__LIST", offset.to_i, offset.to_i + limit.to_i - 1)
        return [] if keys.empty?
        result = []
        if $openc3_redis_cluster
          # No pipelining for cluster mode
          # because it requires using the same shard for all keys
          keys.each do |key|
            result << self.store.hget("#{RUNNING_PRIMARY_KEY}__#{scope}", key)
          end
        else
          result = self.store.redis_pool.pipelined do
            keys.each do |key|
              self.store.hget("#{RUNNING_PRIMARY_KEY}__#{scope}", key)
            end
          end
        end
        result = result.map do |r|
          if r.nil?
            nil
          else
            JSON.parse(r, :allow_nan => true, :create_additions => true)
          end
        end
        return result
      else
        keys = self.store.zrevrange("#{COMPLETED_PRIMARY_KEY}__#{scope}__LIST", offset.to_i, offset.to_i + limit.to_i - 1)
        return [] if keys.empty?
        result = []
        if $openc3_redis_cluster
          # No pipelining for cluster mode
          # because it requires using the same shard for all keys
          keys.each do |key|
            result << self.store.hget("#{COMPLETED_PRIMARY_KEY}__#{scope}", key)
          end
        else
          result = self.store.redis_pool.pipelined do
            keys.each do |key|
              self.store.hget("#{COMPLETED_PRIMARY_KEY}__#{scope}", key)
            end
          end
        end
        result = result.map do |r|
          if r.nil?
            nil
          else
            JSON.parse(r, :allow_nan => true, :create_additions => true)
          end
        end
        return result
      end
    end

    def self.count(scope:, type: "running")
      if type == "running"
        return self.store.zcount("#{RUNNING_PRIMARY_KEY}__#{scope}__LIST", 0, Float::INFINITY)
      else
        return self.store.zcount("#{COMPLETED_PRIMARY_KEY}__#{scope}__LIST", 0, Float::INFINITY)
      end
    end

    def initialize(
      name:, # id
      state:, # spawning, init, running, paused, waiting, error, breakpoint, crashed, stopped, completed, completed_errors, killed
      shard: 0, # Future enhancement of script runner shards
      filename:, # The initial filename
      current_filename: nil, # The current filename
      line_no: 0, # The current line number
      start_line_no: 1, # The line number to start the script at
      end_line_no: nil, # The line number to end the script at
      username:, # The username of the person who started the script
      user_full_name:, # The full name of the person who started the script
      start_time:, # The time the script started ISO format
      end_time: nil, # The time the script ended ISO format
      disconnect: false,
      environment: nil,
      suite_runner: nil,
      errors: nil,
      pid: nil,
      log: nil,
      report: nil,
      script_engine: nil,
      updated_at: nil,
      scope:
    )
      @state = state
      if is_complete?()
        super("#{COMPLETED_PRIMARY_KEY}__#{scope}", name: name, updated_at: updated_at, plugin: nil, scope: scope)
      else
        super("#{RUNNING_PRIMARY_KEY}__#{scope}", name: name, updated_at: updated_at, plugin: nil, scope: scope)
      end
      @shard = shard.to_i
      @filename = filename
      @current_filename = current_filename
      @line_no = line_no
      @start_line_no = start_line_no
      @end_line_no = end_line_no
      @username = username
      @user_full_name = user_full_name
      @start_time = start_time
      @end_time = end_time
      @disconnect = disconnect
      @environment = environment
      @suite_runner = suite_runner
      @errors = errors
      @pid = pid
      @log = log
      @report = report
      @script_engine = script_engine
    end

    def is_complete?
      return (@state == 'completed' or @state == 'completed_errors' or @state == 'stopped' or @state == 'crashed' or @state == 'killed')
    end

    def state=(new_state)
      # If the state is already a flavor of complete, leave it alone (first wins)
      if not is_complete?()
        @state = new_state
        # If setting to complete, check for errors
        # and set the state to completed_errors if they exist
        if @state == 'completed' and @errors
          @state = 'completed_errors'
        end
      end
    end

    # Update the Redis hash at primary_key and set the field "name"
    # to the JSON generated via calling as_json
    def create(update: false, force: false, queued: false, isoformat: true)
      @updated_at = Time.now.utc.to_nsec_from_epoch

      if queued
        write_store = self.class.store_queued
      else
        write_store = self.class.store
      end
      write_store.hset(@primary_key, @name, JSON.generate(self.as_json(:allow_nan => true), :allow_nan => true))

      # Also add to ordered set on create
      write_store.zadd(@primary_key + "__LIST", @name.to_i, @name) if not update
    end

    def update(force: false, queued: false)
      # Magically handle the change from running to completed
      if is_complete?() and @primary_key == "#{RUNNING_PRIMARY_KEY}__#{@scope}"
        # Destroy the running key
        destroy(queued: queued)
        @destroyed = false

        # Move to completed
        @primary_key = "#{COMPLETED_PRIMARY_KEY}__#{@scope}"
        create(update: false, force: force, queued: queued, isoformat: true)
      else
        create(update: true, force: force, queued: queued, isoformat: true)
      end
    end

    # Delete the model from the Store
    def destroy(queued: false)
      @destroyed = true
      undeploy()
      if queued
        write_store = self.class.store_queued
      else
        write_store = self.class.store
      end
      write_store.hdel(@primary_key, @name)
      # Also remove from ordered set
      write_store.zremrangebyscore(@primary_key + "__LIST", @name.to_i, @name.to_i)
    end

    def as_json(*a)
      {
        'name' => @name,
        'state' => @state,
        'shard' => @shard,
        'filename' => @filename,
        'current_filename' => @current_filename,
        'line_no' => @line_no,
        'start_line_no' => @start_line_no,
        'end_line_no' => @end_line_no,
        'username' => @username,
        'user_full_name' => @user_full_name,
        'start_time' => @start_time,
        'end_time' => @end_time,
        'disconnect' => @disconnect,
        'environment' => @environment,
        'suite_runner' => @suite_runner,
        'errors' => @errors,
        'pid' => @pid,
        'log' => @log,
        'report' => @report,
        'script_engine' => @script_engine,
        'updated_at' => @updated_at,
        'scope' => @scope
      }
    end
  end
end
