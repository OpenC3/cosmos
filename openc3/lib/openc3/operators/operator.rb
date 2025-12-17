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
    attr_reader :name

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
      # However, if the MicroserviceOperator is spawning the processes it sets
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
      ENV.each do |key, _value|
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
      @name = "#{Socket.gethostname}__#{@process.pid}"
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
        begin
          Process.kill("SIGINT", @process.pid) if @process # Signal the process to stop
        rescue Errno::ESRCH
          # Process already gone
        end
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
      FileUtils.remove_entry_secure(@temp_dir, true)
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
          message = "STDOUT #{stdout.length} bytes from #{cmd_line()}:"
          STDOUT.puts Logger.build_log_data(Logger::INFO_LEVEL, message, user: nil, type: OpenC3::Logger::LOG, url: nil).as_json().to_json(allow_nan: true)
          STDOUT.puts stdout
        end
        stderr = @process.io.stderr.extract
        if stderr.length > 0
          message = "STDERR #{stderr.length} bytes from #{cmd_line()}:"
          STDERR.puts Logger.build_log_data(Logger::ERROR_LEVEL, message, user: nil, type: OpenC3::Logger::LOG, url: nil).as_json().to_json(allow_nan: true)
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
    PROCESS_SHUTDOWN_SECONDS = 5.0

    def initialize
      Logger.level = Logger::INFO
      Logger.microservice_name = 'MicroserviceOperator'

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
          @new_processes.each { |_name, p| p.start }
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

          @changed_processes.each { |_name, p| p.start }
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
        @processes.each do |_name, p|
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
      # Make a copy so we don't mutate original
      processes = processes.dup

      Logger.info("Commanding soft stops...")
      processes.each { |_name, p| p.soft_stop }
      start_time = Time.now
      # Allow sufficient time for processes to shutdown cleanly
      while (Time.now - start_time) < PROCESS_SHUTDOWN_SECONDS
        processes_to_remove = []
        processes.each do |name, p|
          unless p.alive?
            processes_to_remove << name
            Logger.debug("Soft stop process successful: #{p.cmd_line}", scope: p.scope)
          end
        end
        processes_to_remove.each do |name|
          processes.delete(name)
        end
        if processes.length <= 0
          Logger.debug("Soft stop all successful")
          break
        end
        sleep(0.1)
      end
      if processes.length > 0
        Logger.debug("Commanding hard stops...")
        processes.each { |_name, p| p.hard_stop }
      end
    end

    def shutdown
      @shutdown = true
      @mutex.synchronize do
        Logger.info("Shutting down processes...")
        shutdown_processes(@processes)
        Logger.info("Shutting down processes complete")
        @shutdown_complete = true
      end
    end

    def run
      # Use at_exit to shutdown cleanly
      at_exit { shutdown() }

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
        sleep(0.1)
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
