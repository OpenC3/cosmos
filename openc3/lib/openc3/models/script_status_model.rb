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

    attr_accessor :state # spawning, init, running, paused, waiting, error, crash, stopped, breakpoint, complete, complete_errors
    attr_accessor :shard
    attr_accessor :filename
    attr_accessor :current_filename
    attr_accessor :line_no
    attr_accessor :username
    attr_accessor :user_full_name
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :disconnect
    attr_accessor :environment
    attr_accessor :suite_runner
    attr_accessor :errors
    attr_accessor :pid

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:, type: "auto")
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

    def self.all(scope:, type: "running")
      if type == "running"
        return super("#{RUNNING_PRIMARY_KEY}__#{scope}")
      else
        return super("#{COMPLETED_PRIMARY_KEY}__#{scope}")
      end
    end

    def initialize(
      name:,
      state:, # spawning, init, running, paused, waiting, error, crash, stopped, breakpoint, complete, complete_errors
      shard: 0,
      filename:,
      current_filename: nil,
      line_no: nil,
      username:,
      user_full_name:,
      start_time:,
      end_time: nil,
      disconnect: false,
      environment: nil,
      suite_runner: false,
      errors: nil,
      pid: nil,
      updated_at: nil,
      scope:
    )
      @state = state
      if @state == 'complete' or @state == 'complete_errors' or @state == 'stopped' or @state == 'crash'
        super("#{COMPLETED_PRIMARY_KEY}__#{scope}", name: name, updated_at: updated_at, plugin: nil, scope: scope)
      else
        super("#{RUNNING_PRIMARY_KEY}__#{scope}", name: name, updated_at: updated_at, plugin: nil, scope: scope)
      end
      @shard = shard.to_i
      @filename = filename
      @current_filename = current_filename
      @line_no = line_no
      @username = username
      @user_full_name = user_full_name
      @start_time = start_time
      @end_time = end_time
      @disconnect = disconnect
      @environment = environment
      @suite_runner = suite_runner
      @errors = errors
      @pid = pid
    end

    def update(force: false, queued: false)
      # Magically handle the change from running to completed
      if @state == 'complete' or @state == 'complete_errors' or @state == 'stopped' or @state == 'crash'
        # We are complete
        if @primary_key == "#{RUNNING_PRIMARY_KEY}__#{@scope}"
          # Destroy the running key
          destroy()
          @destroyed = false

          # Move to completed
          @primary_key = "#{COMPLETED_PRIMARY_KEY}__#{@scope}"
          create(update: false, force: force, queued: queued)
        end
      else
        create(update: true, force: force, queued: queued)
      end
    end

    def as_json(*a)
      {
        'name' => @name,
        'state' => @state,
        'shard' => @shard,
        'filename' => @filename,
        'current_filename' => @current_filename,
        'line_no' => @line_no,
        'username' => @username,
        'user_full_name' => @user_full_name,
        'start_time' => @start_time,
        'end_time' => @end_time,
        'disconnect' => @disconnect,
        'environment' => @environment,
        'suite_runner' => @suite_runner,
        'errors' => @errors,
        'pid' => @pid,
        'updated_at' => @updated_at,
        'scope' => @scope
      }
    end
  end
end
