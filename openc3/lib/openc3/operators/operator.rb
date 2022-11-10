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

require 'childprocess'
require 'openc3'
require 'fileutils'
require 'tempfile'

module OpenC3
  # Class to prevent an infinitely growing log file
  class OperatorProcessIO < Tempfile
    def initialize(label, max_start_lines: 100, max_end_lines: 100)
      super(label)
      @max_start_lines = max_start_lines
      @max_end_lines = max_end_lines
      @start_lines = []
      @end_lines = []
    end

    def extract
      rewind()
      data = read()
      truncate(0)
      rewind()

      # Save a set number of lines for unexpected death messages
      lines = data.split("\n")
      lines.each do |line|
        if @start_lines.length < @max_start_lines
          @start_lines << line
        else
          @end_lines << line
        end
      end
      if @end_lines.length > @max_end_lines
        @end_lines = @end_lines[(@end_lines.length - @max_end_lines)..-1]
      end

      return data
    end

    def finalize
      extract()
      close()
      unlink()

      output = ''
      output << @start_lines.join("\n")
      if @end_lines.length >= @max_end_lines
        output << "\n...\n"
        output << @end_lines.join("\n")
      elsif @end_lines.length > 0
        output << @end_lines.join("\n")
      end
      output << "\n"
      output
    end
  end

  class OperatorProcess
    attr_accessor :process_definition
    attr_accessor :work_dir
    attr_accessor :env
    attr_accessor :new_temp_dir
    attr_reader :temp_dir
    attr_reader :scope

    def self.setup
      # Perform any setup steps necessary
    end

    # container is not used, it's just here for Enterprise
    def initialize(process_definition, work_dir: '/openc3/lib/openc3/microservices', temp_dir: nil, env: {}, scope:, container: nil, config: nil)
      @process = nil
      @process_definition = process_definition
      @work_dir = work_dir
      @temp_dir = temp_dir
      @new_temp_dir = temp_dir
      @env = env
      @scope = scope
      # @config only used in start to help print a better Logger message
      @config = config
    end

    def cmd_line
      # In ProcessManager processes, the process_definition is the actual thing run
      # e.g. OpenC3::ProcessManager.instance.spawn(["ruby", "/openc3/bin/openc3cli", "load", ...])
      # However, if the MicroserviceOperator is spawning the proceses it sets
      # process_definition = ["ruby", "plugin_microservice.rb"]
      # which then calls exec(*@config["cmd"]) to actually run
      # So check if the @config['cmd'] is defined to give the user more info in the log
      cmd_line_text = @process_definition.join(' ')
      if @config && @config['cmd']
        cmd_line_text = @config['cmd'].join(' ')
      end
      return cmd_line_text
    end

    def start
      @temp_dir = @new_temp_dir
      @new_temp_dir = nil

      Logger.info("Starting: #{cmd_line()}", scope: @scope)

      @process = ChildProcess.build(*@process_definition)
      # This lets the ChildProcess use the parent IO ... but it breaks unit tests
      # @process.io.inherit!
      @process.cwd = @work_dir
      # Spawned process should not be controlled by same Bundler constraints as spawning process
      ENV.each do |key, value|
        if key =~ /^BUNDLER/
          @process.environment[key] = nil
        end
      end
      @env['RUBYOPT'] = nil # Removes loading bundler setup
      @env.each do |key, value|
        @process.environment[key] = value
      end
      @process.environment['OPENC3_SCOPE'] = @scope
      @process.io.stdout = OperatorProcessIO.new('microservice-stdout')
      @process.io.stderr = OperatorProcessIO.new('microservice-stderr')
      @process.start
    end

    def alive?
      if @process
        @process.alive?
      else
        false
      end
    end

    def exit_code
      if @process
        @process.exit_code
      else
        nil
      end
    end

    def soft_stop
      Thread.new do
        Logger.info("Soft shutting down process: #{cmd_line()}", scope: @scope)
        Process.kill("SIGINT", @process.pid) if @process # Signal the process to stop
      end
    end

    def hard_stop
      if @process and !@process.exited?
        # Redis may be down at this point so just catch any Logger errors
        begin
          Logger.info("Hard shutting down process: #{cmd_line()}", scope: @scope)
        rescue Exception
        end
        @process.stop
      end
      FileUtils.remove_entry(@temp_dir) if @temp_dir and File.exist?(@temp_dir)
      @process = nil
    end

    def stdout
      @process.io.stdout
    end

    def stderr
      @process.io.stderr
    end

    def output_increment
      if @process
        stdout = @process.io.stdout.extract
        if stdout.length > 0
          STDOUT.puts "STDOUT #{stdout.length} bytes from #{cmd_line()}:"
          STDOUT.puts stdout
        end
        stderr = @process.io.stderr.extract
        if stderr.length > 0
          STDERR.puts "STDERR #{stderr.length} bytes from #{cmd_line()}:"
          STDERR.puts stderr
        end
      end
    end

    # This is method is used in here and in ProcessManager
    def extract_output
      output = ''
      if @process
        stdout = @process.io.stdout.finalize
        stderr = @process.io.stderr.finalize

        # Always include the Stdout header for consistency and to show the option
        output << "Stdout:\n"
        output << stdout

        # Always include the nStderr header for consistency and to show the option
        output << "\nStderr:\n"
        output << stderr
      end
      output
    end
  end

  class Operator
    attr_reader :processes, :cycle_time

    @@instance = nil

    CYCLE_TIME = 5.0 # cycle time to check for new microservices

    def initialize
      Logger.level = Logger::INFO
      # TODO: This is pretty generic. Can we pass in more information to help identify the operator?
      Logger.microservice_name = 'MicroserviceOperator'
      Logger.tag = "operator.log"

      OperatorProcess.setup()
      @cycle_time = (ENV['OPERATOR_CYCLE_TIME'] and ENV['OPERATOR_CYCLE_TIME'].to_f) || CYCLE_TIME # time in seconds

      @ruby_process_name = ENV['OPENC3_RUBY']
      if RUBY_ENGINE != 'ruby'
        @ruby_process_name ||= 'jruby'
      else
        @ruby_process_name ||= 'ruby'
      end

      @processes = {}
      @new_processes = {}
      @changed_processes = {}
      @removed_processes = {}
      @mutex = Mutex.new
      @shutdown = false
      @shutdown_complete = false
    end

    def update
      raise "Implement in subclass"
    end

    def start_new
      @mutex.synchronize do
        if @new_processes.length > 0
          # Start all the processes
          Logger.info("#{self.class} starting each new process...")
          @new_processes.each { |name, p| p.start }
          @new_processes = {}
        end
      end
    end

    def respawn_changed
      @mutex.synchronize do
        if @changed_processes.length > 0
          Logger.info("Cycling #{@changed_processes.length} changed microservices...")
          shutdown_processes(@changed_processes)
          break if @shutdown

          @changed_processes.each { |name, p| p.start }
          @changed_processes = {}
        end
      end
    end

    def remove_old
      @mutex.synchronize do
        if @removed_processes.length > 0
          Logger.info("Shutting down #{@removed_processes.length} removed microservices...")
          shutdown_processes(@removed_processes)
          @removed_processes = {}
        end
      end
    end

    def respawn_dead
      @mutex.synchronize do
        @processes.each do |name, p|
          break if @shutdown
          p.output_increment
          unless p.alive?
            # Respawn process
            output = p.extract_output
            Logger.error("Unexpected process died... respawning! #{p.cmd_line}\n#{output}\n", scope: p.scope)
            p.start
          end
        end
      end
    end

    def shutdown_processes(processes)
      processes.each { |name, p| p.soft_stop }
      sleep(2) # TODO: This is an arbitrary sleep of 2s ...
      processes.each { |name, p| p.hard_stop }
    end

    def run
      # Use at_exit to shutdown cleanly
      at_exit do
        @shutdown = true
        @mutex.synchronize do
          Logger.info("Shutting down processes...")
          shutdown_processes(@processes)
          @shutdown_complete = true
        end
      end

      # Monitor processes and respawn if died
      Logger.info("#{self.class} Monitoring processes every #{@cycle_time} sec...")
      loop do
        update()
        remove_old()
        respawn_changed()
        start_new()
        respawn_dead()
        break if @shutdown

        sleep(@cycle_time)
        break if @shutdown
      end

      loop do
        break if @shutdown_complete
        sleep(1)
      end
    ensure
      Logger.info("#{self.class} shutdown complete")
    end

    def stop
      @shutdown = true
    end

    def self.run
      @@instance = self.new
      @@instance.run
    end

    def self.processes
      @@instance.processes
    end

    def self.instance
      @@instance
    end
  end
end
