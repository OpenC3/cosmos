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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# This file contains top level functions in the OpenC3 namespace

require 'digest'
require 'open3'
require 'openc3/core_ext'
require 'openc3/version'
require 'openc3/utilities/logger'
require 'socket'
require 'pathname'

$openc3_chdir_mutex = Mutex.new

# If a hazardous command is sent through the {OpenC3::Api} this error is raised.
# {OpenC3::Script} rescues the error and prompts the user to continue.
class HazardousError < StandardError
  attr_accessor :target_name
  attr_accessor :cmd_name
  attr_accessor :cmd_params
  attr_accessor :hazardous_description
  attr_accessor :formatted # formatted command for use in resending original

  def to_s
    string = "#{target_name} #{cmd_name} with #{cmd_params} is Hazardous "
    string << "due to '#{hazardous_description}'" if hazardous_description
    # Pass along the original formatted command so it can be resent
    string << ".\n#{formatted}"
  end
end

class CriticalCmdError < StandardError
  attr_accessor :uuid
  attr_accessor :username
  attr_accessor :target_name
  attr_accessor :cmd_name
  attr_accessor :cmd_params
  attr_accessor :cmd_string
  attr_accessor :options
end

# If a disabled command is sent through the {OpenC3::Api} this error is raised.
class DisabledError < StandardError
  attr_accessor :target_name
  attr_accessor :cmd_name

  def to_s
    "#{target_name} #{cmd_name} is Disabled"
  end
end

# OpenC3 is almost
# wholly contained within the OpenC3 module. OpenC3 also extends some of the
# core Ruby classes to add additional functionality.

module OpenC3
  BASE_PWD = Dir.pwd

  # FatalErrors cause an exit but are not as dangerous as other errors.
  # They are used for known issues and thus we don't need a full error report.
  class FatalError < StandardError; end

  # Global mutex for the OpenC3 module
  OPENC3_MUTEX = Mutex.new

  # Path to OpenC3 Gem based on location of top_level.rb
  PATH = File.expand_path(File.join(File.dirname(__FILE__), '../..'))
  PATH.freeze

  # Header to put on all marshal files created by OpenC3
  OPENC3_MARSHAL_HEADER = "ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE} patchlevel #{RUBY_PATCHLEVEL}) [#{RUBY_PLATFORM}] OpenC3 #{OPENC3_VERSION}"

  # Disables the Ruby interpreter warnings such as when redefining a constant
  def self.disable_warnings
    saved_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = saved_verbose
  end

  # Adds a path to the global Ruby search path
  #
  # @param path [String] Directory path
  def self.add_to_search_path(path, front = true)
    path = File.expand_path(path)
    $:.delete(path)
    if front
      $:.unshift(path)
    else # Back
      $: << path
    end
  end

  # Creates a marshal file by serializing the given obj
  #
  # @param marshal_filename [String] Name of the marshal file to create
  # @param obj [Object] The object to serialize to the file
  def self.marshal_dump(marshal_filename, obj)
    File.open(marshal_filename, 'wb') do |file|
      file.write(OPENC3_MARSHAL_HEADER)
      file.write(Marshal.dump(obj))
    end
  rescue Exception => e
    begin
      File.delete(marshal_filename)
    rescue Exception
      # Oh well - we tried
    end
    if e.class == TypeError and e.message =~ /Thread::Mutex/
      original_backtrace = e.backtrace
      e = e.exception("Mutex exists in a packet.  Note: Packets must not be read during class initializers for Conversions, Limits Responses, etc.: #{e}")
      e.set_backtrace(original_backtrace)
    end
    self.handle_fatal_exception(e)
  end

  # Loads the marshal file back into a Ruby object
  #
  # @param marshal_filename [String] Name of the marshal file to load
  def self.marshal_load(marshal_filename)
    openc3_marshal_header = nil
    data = nil
    File.open(marshal_filename, 'rb') do |file|
      openc3_marshal_header = file.read(OPENC3_MARSHAL_HEADER.length)
      data = file.read
    end
    if openc3_marshal_header == OPENC3_MARSHAL_HEADER
      return Marshal.load(data)
    else
      Logger.warn "Marshal load failed with invalid marshal file: #{marshal_filename}"
      return nil
    end
  rescue Exception => e
    if File.exist?(marshal_filename)
      Logger.error "Marshal load failed with exception: #{marshal_filename}\n#{e.formatted}"
    else
      Logger.info "Marshal file does not exist: #{marshal_filename}"
    end

    # Try to delete the bad marshal file
    begin
      File.delete(marshal_filename)
    rescue Exception
      # Oh well - we tried
    end
    self.handle_fatal_exception(e) if File.exist?(marshal_filename)
    return nil
  end

  # Executes the command in a new Ruby Thread.
  #
  # @param command [String] The command to execute via the 'system' call
  def self.run_process(command)
    thread = nil
    thread = Thread.new do
      system(command)
    end
    # Wait for the thread and process to start
    sleep 0.01 until !thread.status.nil?
    sleep 0.1
    thread
  end

  # Executes the command in a new Ruby Thread.  Will print the output if the
  # process produces any output
  #
  # @param command [String] The command to execute via the 'system' call
  def self.run_process_check_output(command)
    thread = nil
    thread = Thread.new do
      output, _ = Open3.capture2e(command)
      if !output.empty?
        # Ignore modalSession messages on Mac Mavericks
        new_output = ''
        output.each_line do |line|
          new_output << line if !/modalSession/.match?(line)
        end
        output = new_output

        if !output.empty?
          Logger.error output
          self.write_unexpected_file(output)
        end
      end
    end
    # Wait for the thread and process to start
    sleep 0.01 until !thread.status.nil?
    sleep 0.1
    thread
  end

  # Runs a hash algorithm over one or more files and returns the Digest object.
  # Handles windows/unix new line differences but changes in whitespace will
  # change the hash sum.
  #
  # Usage:
  #   digest = OpenC3.hash_files(files, additional_data, hashing_algorithm)
  #   digest.digest # => the 16 bytes of digest
  #   digest.hexdigest # => the formatted string in hex
  #
  # @param filenames [Array<String>] List of files to read and calculate a hashing
  #   sum on
  # @param additional_data [String] Additional data to add to the hashing sum
  # @param hashing_algorithm [String] Hashing algorithm to use
  # @return [Digest::<algorithm>] The hashing sum object
  def self.hash_files(filenames, additional_data = nil, hashing_algorithm = 'SHA256')
    digest = Digest.const_get(hashing_algorithm).public_send('new')

    filenames.each do |filename|
      next if File.directory?(filename)

      # Read the file's data and add to the running hashing sum
      digest << File.read(filename)
    end
    digest << additional_data if additional_data
    digest
  end

  # Opens a timestamped log file for writing. The opened file is yielded back
  # to the block.
  #
  # @param filename [String] String to append to the exception log filename.
  #   The filename will start with a date/time stamp.
  # @param log_dir [String] By default this method will write to the OpenC3
  #   default log directory. By setting this parameter you can override the
  #   directory the log will be written to.
  # @yieldparam file [File] The log file
  # @return [String|nil] The fully pathed log filename or nil if there was
  #   an error creating the log file.
  def self.create_log_file(filename, log_dir = nil)
    log_file = nil
    begin
      # If this has an error we won't be able
      # to determine the log path but we still want to write the log.
      log_dir = System.instance.paths['LOGS'] unless log_dir
      # Make sure the log directory exists
      raise unless File.exist?(log_dir)
    rescue Exception
      log_dir = nil # Reset log dir since it failed above
      # First check for ./logs
      log_dir = './logs' if File.exist?('./logs')
      # Prefer ./outputs/logs if it exists
      log_dir = './outputs/logs' if File.exist?('./outputs/logs')
      # If all else fails just use the local directory
      log_dir = '.' unless log_dir
    end
    log_file = File.join(log_dir,
                          File.build_timestamped_filename([filename]))
    # Check for the log file existing. This could happen if this method gets
    # called more than once in the same second.
    if File.exist?(log_file)
      sleep 1.01 # Sleep before rebuilding the timestamp to get something unique
      log_file = File.join(log_dir,
                            File.build_timestamped_filename([filename]))
    end
    begin
      OPENC3_MUTEX.synchronize do
        file = File.open(log_file, 'w')
        yield file
      ensure
        file.close unless file.closed?
        File.chmod(0444, log_file) # Make file read only
      end
    rescue Exception
      # Ensure we always return
    end
    log_file = File.expand_path(log_file)
    return log_file
  end

  # Writes a log file with information about the current configuration
  # including the Ruby version, OpenC3 version, whether you are on Windows, the
  # OpenC3 path, and the Ruby path along with the exception that
  # is passed in.
  #
  # @param [String] filename String to append to the exception log filename.
  #   The filename will start with a date/time stamp.
  # @param [String] log_dir By default this method will write to the OpenC3
  #   default log directory. By setting this parameter you can override the
  #   directory the log will be written to.
  # @return [String|nil] The fully pathed log filename or nil if there was
  #   an error creating the log file.
  def self.write_exception_file(exception, filename = 'exception', log_dir = nil)
    log_file = create_log_file(filename, log_dir) do |file|
      file.puts "Exception:"
      if exception
        file.puts exception.formatted
        file.puts
      else
        file.puts "No Exception Given"
        file.puts caller.join("\n")
        file.puts
      end
      file.puts "Caller Backtrace:"
      file.puts caller().join("\n")
      file.puts

      file.puts "Ruby Version: ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE} patchlevel #{RUBY_PATCHLEVEL}) [#{RUBY_PLATFORM}]"
      file.puts "Rubygems Version: #{Gem::VERSION}"
      file.puts "OpenC3 Version: #{OpenC3::VERSION}"
      file.puts "OpenC3::PATH: #{OpenC3::PATH}"
      file.puts ""
      file.puts "Environment:"
      file.puts "RUBYOPT: #{ENV['RUBYOPT']}"
      file.puts "RUBYLIB: #{ENV['RUBYLIB']}"
      file.puts "GEM_PATH: #{ENV['GEM_PATH']}"
      file.puts "GEMRC: #{ENV['GEMRC']}"
      file.puts "RI_DEVKIT: #{ENV['RI_DEVKIT']}"
      file.puts "GEM_HOME: #{ENV['GEM_HOME']}"
      file.puts "PYTHONUSERBASE: #{ENV['PYTHONUSERBASE']}"
      file.puts "PATH: #{ENV['PATH']}"
      file.puts ""
      file.puts "Ruby Path:\n  #{$:.join("\n  ")}\n\n"
      file.puts "Gems:"
      Gem.loaded_specs.values.map { |x| file.puts "#{x.name} #{x.version} #{x.platform}" }
      file.puts ""
      file.puts "All Threads Backtraces:"
      Thread.list.each do |thread|
        file.puts thread.backtrace.join("\n")
        file.puts
      end
      file.puts ""
      file.puts ""
    ensure
      file.close
    end
    return log_file
  end

  # Writes a log file with information about unexpected output
  #
  # @param [String] text The unexpected output text
  # @param [String] filename String to append to the exception log filename.
  #   The filename will start with a date/time stamp.
  # @param [String] log_dir By default this method will write to the OpenC3
  #   default log directory. By setting this parameter you can override the
  #   directory the log will be written to.
  # @return [String|nil] The fully pathed log filename or nil if there was
  #   an error creating the log file.
  def self.write_unexpected_file(text, filename = 'unexpected', log_dir = nil)
    log_file = create_log_file(filename, log_dir) do |file|
      file.puts "Unexpected Output:\n\n"
      file.puts text
    ensure
      file.close
    end
    return log_file
  end

  # Write a message to the Logger, write an exception file, and popup a GUI
  # window if try_gui. Finally 'exit 1' is called to end the calling program.
  #
  # @param error [Exception] The exception to handle
  # @param try_gui [Boolean] Whether to try and create a GUI exception popup
  def self.handle_fatal_exception(error, _try_gui = true)
    unless SystemExit === error or SignalException === error
      $openc3_fatal_exception = error
      self.write_exception_file(error)
      Logger.fatal "Fatal Exception! Exiting..."
      Logger.fatal error.formatted
      if $stdout != STDOUT
        $stdout = STDOUT
        Logger.fatal "Fatal Exception! Exiting..."
        Logger.fatal error.formatted
      end
      sleep 1 # Allow the messages to be printed and then crash
      exit 1
    else
      exit 0
    end
  end

  # CriticalErrors are errors that need to be brought to a user's attention but
  # do not cause an exit. A good example is if the packet log writer fails and
  # can no longer write the log file. Write a message to the Logger, write an
  # exception file, and popup a GUI window if try_gui. Ensure the GUI only
  # comes up once so this method can be called over and over by failing code.
  #
  # @param error [Exception] The exception to handle
  # @param try_gui [Boolean] Whether to try and create a GUI exception popup
  def self.handle_critical_exception(error, _try_gui = true)
    Logger.error "Critical Exception! #{error.formatted}"
    self.write_exception_file(error)
  end

  # Creates a Ruby Thread to run the given block. Rescues any exceptions and
  # retries the threads the given number of times before handling the thread
  # death by calling {OpenC3.handle_fatal_exception}.
  #
  # @param name [String] Name of the thread
  # @param retry_attempts [Integer] The number of times to allow the thread to
  #   restart before exiting
  def self.safe_thread(name, retry_attempts = 0)
    Thread.new do
      retry_count = 0
      begin
        yield
      rescue => e
        Logger.error "#{name} thread unexpectedly died. Retries: #{retry_count} of #{retry_attempts}"
        Logger.error e.formatted
        retry_count += 1
        if retry_count <= retry_attempts
          self.write_exception_file(e)
          retry
        end
        handle_fatal_exception(e)
      end
    end
  end

  # Require the class represented by the filename. This uses the standard Ruby
  # convention of having a single class per file where the class name is camel
  # cased and filename is lowercase with underscores.
  #
  # @param class_name_or_class_filename [String] The name of the class or the file which contains the
  #   Ruby class to require
  # @param log_error [Boolean] Whether to log an error if we can't require the class
  def self.require_class(class_name_or_class_filename, log_error = true)
    if class_name_or_class_filename.downcase[-3..-1] == '.rb' or (class_name_or_class_filename[0] == class_name_or_class_filename[0].downcase)
      class_filename = class_name_or_class_filename
      class_name = class_filename.filename_to_class_name
    else
      class_name = class_name_or_class_filename
      class_filename = class_name.class_name_to_filename
    end
    return class_name.to_class if class_name.to_class and defined? class_name.to_class

    self.require_file(class_filename, log_error)
    klass = class_name.to_class
    raise "Ruby class #{class_name} not found" unless klass

    klass
  end

  # Requires a file with a standard error message if it fails
  #
  # @param filename [String] The name of the file to require
  # @param log_error [Boolean] Whether to log an error if we can't require the class
  def self.require_file(filename, log_error = true)
    require filename
  rescue Exception => e
    msg = "Unable to require #{filename} due to #{e.message}. "\
          "Ensure #{filename} is in the OpenC3 lib directory."
    Logger.error msg if log_error
    raise $!, msg, $!.backtrace
  end

  # Temporarily set the working directory during a block
  # Working directory is global, so this can make other threads wait
  # Ruby Dir.chdir with block always throws an error if multiple threads
  # call Dir.chdir
  def self.set_working_dir(working_dir, &)
    if $openc3_chdir_mutex.owned?
      set_working_dir_internal(working_dir, &)
    else
      $openc3_chdir_mutex.synchronize do
        set_working_dir_internal(working_dir, &)
      end
    end
  end

  # Private helper method
  def self.set_working_dir_internal(working_dir)
    current_dir = Dir.pwd
    Dir.chdir(working_dir)
    begin
      yield
    ensure
      Dir.chdir(current_dir)
    end
  end

  # Attempt to gracefully kill a thread
  # @param owner Object that owns the thread and may have a graceful_kill method
  # @param thread The thread to gracefully kill
  # @param graceful_timeout Timeout in seconds to wait for it to die gracefully
  # @param timeout_interval How often to poll for aliveness
  # @param hard_timeout Timeout in seconds to wait for it to die ungracefully
  def self.kill_thread(owner, thread, graceful_timeout = 1, timeout_interval = 0.01, hard_timeout = 1)
    if thread
      if owner and owner.respond_to? :graceful_kill
        if Thread.current != thread
          owner.graceful_kill
          end_time = Time.now.sys + graceful_timeout
          while thread.alive? && ((end_time - Time.now.sys) > 0)
            sleep(timeout_interval)
          end
        else
          Logger.warn "Threads cannot graceful_kill themselves"
        end
      elsif owner
        Logger.info "Thread owner #{owner.class} does not support graceful_kill"
      end
      if thread.alive?
        # If the thread dies after alive? but before backtrace, bt will be nil.
        bt = thread.backtrace

        # Graceful failed
        msg =  "Failed to gracefully kill thread:\n"
        msg << "  Caller Backtrace:\n  #{caller().join("\n  ")}\n"
        msg << "  \n  Thread Backtrace:\n  #{bt.join("\n  ")}\n" if bt
        msg << "\n"
        Logger.warn msg
        thread.kill
        end_time = Time.now.sys + hard_timeout
        while thread.alive? && ((end_time - Time.now.sys) > 0)
          sleep(timeout_interval)
        end
      end
      if thread.alive?
        Logger.error "Failed to kill thread"
      end
    end
  end

  # Close a socket in a manner that ensures that any reads blocked in select
  # will unblock across platforms
  # @param socket The socket to close
  def self.close_socket(socket)
    if socket
      # Calling shutdown and then sleep seems to be required
      # to get select to reliably unblock on linux
      begin
        socket.shutdown(:RDWR)
        sleep(0)
      rescue Exception
        # Oh well we tried
      end
      begin
        socket.close unless socket.closed?
      rescue Exception
        # Oh well we tried
      end
    end
  end
end

# The following code makes most older COSMOS 5 plugins still work with OpenC3
# New plugins should only use openc3 paths and module OpenC3
unless ENV['OPENC3_NO_COSMOS_COMPATIBILITY']
  Cosmos = OpenC3
  ENV['COSMOS_SCOPE'] = ENV['OPENC3_SCOPE']
  module CosmosCompatibility
    def require(*args)
      filename = args[0]
      if filename[0..6] == "cosmos/"
        filename[0..6] = "openc3/"
      end
      args[0] = filename
      super(*args)
    end
    def load(*args)
      filename = args[0]
      if filename[0..6] == "cosmos/"
        filename[0..6] = "openc3/"
      end
      args[0] = filename
      super(*args)
    end
  end
  class Object
    include CosmosCompatibility
  end
end
