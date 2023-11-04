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

require 'openc3/core_ext/class'
require 'openc3/core_ext/time'
require 'openc3/topics/topic'
require 'socket'
require 'logger'
require 'time'
require 'json'

module OpenC3
  # Supports different levels of logging and only writes if the level
  # is exceeded.
  class Logger
    # @return [Boolean] Whether to output the message to stdout
    instance_attr_accessor :stdout

    # @return [Integer] The logging level
    instance_attr_accessor :level

    # @return [String] Additional detail to add to messages
    instance_attr_accessor :detail_string

    # @return [String] Microservice name
    attr_reader :microservice_name

    @@mutex = Mutex.new
    @@instance = nil
    @@scope = ENV['OPENC3_SCOPE']

    # DEBUG only prints DEBUG messages
    DEBUG = ::Logger::DEBUG
    # INFO prints INFO, DEBUG messages
    INFO  = ::Logger::INFO
    # WARN prints WARN, INFO, DEBUG messages
    WARN  = ::Logger::WARN
    # ERROR prints ERROR, WARN, INFO, DEBUG messages
    ERROR = ::Logger::ERROR
    # FATAL prints FATAL, ERROR, WARN, INFO, DEBUG messages
    FATAL = ::Logger::FATAL

    DEBUG_SEVERITY_STRING = 'DEBUG'
    INFO_SEVERITY_STRING = 'INFO'
    WARN_SEVERITY_STRING = 'WARN'
    ERROR_SEVERITY_STRING = 'ERROR'
    FATAL_SEVERITY_STRING = 'FATAL'

    # Types
    LOG = 'log'
    NOTIFICATION = 'notification'
    ALERT = 'alert'

    # @param level [Integer] The initial logging level
    def initialize(level = Logger::INFO)
      @stdout = true
      @level = level
      @detail_string = nil
      @container_name = Socket.gethostname
      @microservice_name = nil
      @no_store = ENV['OPENC3_NO_STORE']
    end

    # Only set the microservice name once (to help with multi microservices)
    def microservice_name=(name)
      @microservice_name = name unless @microservice_name
    end

    def self.microservice_name
      self.instance.microservice_name
    end

    def self.microservice_name=(name)
      self.instance.microservice_name = name
    end

    # @param message [String] The message to print if the log level is at or
    #   below the method name log level.
    # @param block [Proc] Block to call which should return a string to append
    #   to the log message
    def debug(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      log_message(DEBUG_SEVERITY_STRING, message, scope: scope, user: user, type: type, url: url, &block) if @level <= DEBUG
    end

    # (see #debug)
    def info(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      log_message(INFO_SEVERITY_STRING, message, scope: scope, user: user, type: type, url: url, &block) if @level <= INFO
    end

    # (see #debug)
    def warn(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      log_message(WARN_SEVERITY_STRING, message, scope: scope, user: user, type: type, url: url, &block) if @level <= WARN
    end

    # (see #debug)
    def error(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      log_message(ERROR_SEVERITY_STRING, message, scope: scope, user: user, type: type, url: url, &block) if @level <= ERROR
    end

    # (see #debug)
    def fatal(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      log_message(FATAL_SEVERITY_STRING, message, scope: scope, user: user, type: type, url: url, &block) if @level <= FATAL
    end

    # (see #debug)
    def self.debug(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      self.instance.debug(message, scope: scope, user: user, type: type, url: url, &block)
    end

    # (see #debug)
    def self.info(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      self.instance.info(message, scope: scope, user: user, type: type, url: url, &block)
    end

    # (see #debug)
    def self.warn(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      self.instance.warn(message, scope: scope, user: user, type: type, url: url, &block)
    end

    # (see #debug)
    def self.error(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      self.instance.error(message, scope: scope, user: user, type: type, url: url, &block)
    end

    # (see #debug)
    def self.fatal(message = nil, scope: @@scope, user: nil, type: LOG, url: nil, &block)
      self.instance.fatal(message, scope: scope, user: user, type: type, url: url, &block)
    end

    # @return [Logger] The logger instance
    def self.instance
      return @@instance if @@instance

      @@mutex.synchronize do
        @@instance ||= self.new
      end
      @@instance
    end

    def self.scope
      return @@scope
    end

    def self.scope=(scope)
      @@scope = scope
    end

    def scope
      return @@scope
    end

    def scope=(scope)
      @@scope = scope
    end

    protected

    def log_message(severity_string, message, scope:, user:, type:, url:)
      @@mutex.synchronize do
        time = Time.now
        data = { time: time.to_nsec_from_epoch, '@timestamp' => time.xmlschema(3), severity: severity_string }
        data[:microservice_name] = @microservice_name if @microservice_name
        data[:detail] = @detail_string if @detail_string
        data[:user] = user if user # EE: If a user is passed, put its name. Don't include user data if no user was passed.
        if block_given?
          message = yield
        end
        data[:container_name] = @container_name
        data[:log] = message
        data[:type] = type
        data[:url] = url if url
        if @stdout
          case severity_string
          when WARN_SEVERITY_STRING, ERROR_SEVERITY_STRING, FATAL_SEVERITY_STRING
            if ENV['OPENC3_LOG_STDERR']
              $stderr.puts data.as_json(:allow_nan => true).to_json(:allow_nan => true)
              $stderr.flush
            else
              $stdout.puts data.as_json(:allow_nan => true).to_json(:allow_nan => true)
              $stdout.flush
            end
          else
            $stdout.puts data.as_json(:allow_nan => true).to_json(:allow_nan => true)
            $stdout.flush
          end
        end
        unless @no_store
          if scope
            Topic.write_topic("#{scope}__openc3_log_messages", data)
          else
            Topic.write_topic("NOSCOPE__openc3_log_messages", data)
          end
        end
      end
    end
  end
end
