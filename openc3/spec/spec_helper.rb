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

# Redefine Object.load so simplecov doesn't overwrite the results after
# re-loading a file during test.
# def load(file, wrap = false)
#   if defined? SimpleCov
#     SimpleCov.command_name "#{file}#{(Time.now.to_f * 1000).to_i}"
#   end
#   Kernel.load(file, wrap)
# end

require 'rspec'

# NOTE: You MUST require simplecov before anything else!
if !ENV['OPENC3_NO_SIMPLECOV']
  require 'simplecov'
  if ENV['GITHUB_WORKFLOW']
    require 'simplecov-cobertura'
    SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
  else
    SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
  end
  # Explicitly set the command_name so we don't clobber the results
  # of the regular run with the '--tag no_ext' run
  name = "test:unit"
  if RSpec.configuration.filter_manager.inclusions.rules[:no_ext]
    name += ':no_ext'
  end
  SimpleCov.command_name name
  SimpleCov.start do
    merge_timeout 60 * 60 # merge the last hour of results
    add_filter '/spec/' # no coverage on spec files
    root = File.dirname(__FILE__)
    root.to_s
  end
  SimpleCov.at_exit do
    OpenC3.disable_warnings do
      Encoding.default_external = Encoding::UTF_8
      Encoding.default_internal = nil
    end
    SimpleCov.result.format!
  end
end

# Disable Redis and Fluentd in the Logger
ENV['OPENC3_NO_STORE'] = 'true'
ENV['OPENC3_LOGS_BUCKET'] = 'logs'
ENV['OPENC3_TOOLS_BUCKET'] = 'tools'
ENV['OPENC3_CONFIG_BUCKET'] = 'config'
# Set some usernames / passwords
ENV['OPENC3_API_PASSWORD'] = 'password'
ENV['OPENC3_SERVICE_PASSWORD'] = 'openc3service'
ENV['OPENC3_REDIS_USERNAME'] = 'openc3'
ENV['OPENC3_REDIS_PASSWORD'] = 'openc3password'
ENV['OPENC3_BUCKET_USERNAME'] = 'openc3minio'
ENV['OPENC3_BUCKET_PASSWORD'] = 'openc3miniopassword'
ENV['OPENC3_SCOPE'] = 'DEFAULT'
ENV['OPENC3_CLOUD'] = 'local'

module OpenC3
  USERPATH = File.join(File.dirname(File.expand_path(__FILE__)), 'install')
end

require 'openc3/top_level'
require 'openc3/script'
# require 'openc3/utilities/logger'
# Create a easy alias to the base of the spec directory
SPEC_DIR = File.dirname(__FILE__)
$openc3_scope = ENV['OPENC3_SCOPE']
$openc3_token = ENV['OPENC3_API_PASSWORD']
$openc3_authorize = false

require 'openc3/utilities/store_queued'

# Make StoreQueued not queue for unit tests
$store_queued = false
module OpenC3
  class StoreQueued
    alias old_initialize initialize
    def initialize(update_interval)
      if $store_queued
        old_initialize(update_interval)
      else
        @update_interval = update_interval
        @store = store_instance()
      end
    end

    alias old_method_missing method_missing
    def method_missing(message, *args, **kwargs, &)
      if $store_queued
        old_method_missing(message, *args, **kwargs, &)
      else
        @store.public_send(message, *args, **kwargs, &)
      end
    end
  end
end

def setup_system(targets = %w[SYSTEM INST EMPTY])
  result = nil
  capture_io do |stdout|
    require 'openc3/system'
    dir = File.join(__dir__, 'install', 'config', 'targets')
    OpenC3::System.class_variable_set(:@@instance, nil)
    OpenC3::System.instance(targets, dir)
    result = stdout
  end
  result
end

def get_all_redis_keys
  cursor = 0
  keys = []
  loop do
    cursor, result = OpenC3::Store.scan(cursor)
    keys.concat(result)
    cursor = cursor.to_i # cursor is returned as a string
    break if cursor == 0
  end
  keys
end

OpenC3.disable_warnings do
  require 'redis'
  require 'mock_redis'
  class MockRedis
    module StreamMethods
      private

      def with_stream_at(key, &)
        @mutex ||= Mutex.new
        @mutex.synchronize do
          return with_thing_at(key, :assert_streamy, proc { Stream.new }, &)
        end
      end

      def xread(keys, ids, count: nil, block: nil)
        start_time = Time.now
        args = []
        args += ['COUNT', count] if count
        args += ['BLOCK', block.to_i] if block
        result = {}
        keys = keys.is_a?(Array) ? keys : [keys]
        ids = ids.is_a?(Array) ? ids : [ids]
        read_count = 0
        initial_count = count

        while true
          # Loop over each stream
          keys.each_with_index do |key, index|
            if count
              break if read_count >= initial_count
              count = initial_count - read_count

              # Adjust args for calls to read with remaining count
              args[1] = count
            end
            with_stream_at(key) do |stream|
              # Can't block in read because have mutex, and only reading one stream at a time
              data = stream.read(ids[index], *args)

              # Handle actually reading some data
              unless data.empty?
                # Save new data
                if result[key]
                  result[key].concat(data)
                else
                  result[key] = data
                end

                # Keep track of how many we have read so far
                read_count += data.length
              end
            end
          end
          break if read_count > 0 or not block or ((Time.now - start_time) * 1000) > block
          sleep(0.01)
        end
        result
      end
    end
  end
end

def mock_redis
  redis = MockRedis.new
  allow(Redis).to receive(:new).and_return(redis)

  # pool = double(ConnectionPool)
  # allow(pool).to receive(:with) { redis }
  # allow(ConnectionPool).to receive(:new).and_return(pool)
  OpenC3::Store.instance_variable_set(:@instance, nil)
  OpenC3::EphemeralStore.instance_variable_set(:@instance, nil)
  OpenC3::StoreQueued.instance_variable_set(:@instance, nil)
  OpenC3::EphemeralStoreQueued.instance_variable_set(:@instance, nil)
  require 'openc3/models/auth_model'
  OpenC3::AuthModel.set($openc3_token, nil)
  redis
end

OpenC3.disable_warnings do
  require 'aws-sdk-s3'

  def local_s3
    require 'openc3/utilities/s3_autoload.rb'
    require 'local_s3'
    require 'rspec/mocks/standalone'
    local_filesystem_client = LocalS3::ClientLocal.new
    allow(Aws::S3::Client).to receive(:new).and_return(local_filesystem_client)
  end

  def local_s3_unset
    RSpec::Mocks.space.proxy_for(Aws::S3::Client).reset
  end
end

# Set the logger to output everything and capture it all in a StringIO object
# which is yielded back to the block. Then restore everything.
def capture_io(output = false)
  # Set the logger level to DEBUG so we see all output
  OpenC3::Logger.instance.level = Logger::DEBUG
  OpenC3::Logger.stdout = true

  # Create a StringIO object to capture the output
  stdout = StringIO.new('', 'r+')
  $stdout = stdout
  saved_stdout = nil
  OpenC3.disable_warnings do
    # Save the old STDOUT constant value
    saved_stdout = Object.const_get(:STDOUT)

    # Set STDOUT to our StringIO object
    Object.const_set(:STDOUT, $stdout)
  end

  # Yield back the StringIO so they can match against it
  yield stdout

  # Restore the logger to FATAL to prevent all kinds of output
  OpenC3::Logger.level = Logger::FATAL

  # Restore the STDOUT constant
  OpenC3.disable_warnings { Object.const_set(:STDOUT, saved_stdout) }

  # Restore the $stdout global to be STDOUT
  $stdout = STDOUT
  puts stdout.string if output # Print the capture for debugging
end

# Get a list of running threads, ignoring jruby system threads if necessary.
def running_threads
  threads = []
  Thread.list.each do |t|
    if RUBY_ENGINE == 'jruby'
      thread_name = JRuby.reference(t).native_thread.get_name
      unless thread_name == 'Finalizer' or thread_name.include?('JRubyWorker')
        threads << t.inspect
      end
    else
      threads << t.inspect
    end
  end
  return threads
end

# Kill threads that are not "main", ignoring jruby system threads if necessary.
def kill_leftover_threads
  if RUBY_ENGINE == 'jruby'
    if Thread.list.length > 2
      Thread.list.each do |t|
        thread_name = JRuby.reference(t).native_thread.get_name
        if t != Thread.current and thread_name != 'Finalizer' and
             !thread_name.include?('JRubyWorker')
          t.kill
        end
      end
      sleep(0.2)
    end
  else
    if Thread.list.length > 1
      Thread.list.each { |t| t.kill if t != Thread.current }
      sleep(0.2)
    end
  end
end

RSpec.configure do |config|
  # Enforce the new expect() syntax instead of the old should syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
    c.max_formatted_output_length = nil # Prevent RSpec from doing truncation
  end

  # Store standard output global and CONSTANT since we will mess with them
  config.before(:all) do
    $saved_stdout_global = $stdout
    $saved_stdout_const = Object.const_get(:STDOUT)
  end

  # Before each test make sure $stdout and STDOUT are set. They might be messed
  # up if a spec fails in the middle of capture_io and we don't have a chance
  # to return and reset them.
  config.before(:each) do
    $stdout = $saved_stdout_global if $stdout != $saved_stdout_global
    OpenC3.disable_warnings { Object.const_set(:STDOUT, $saved_stdout_const) }
    kill_leftover_threads
  end

  config.after(:each) do
    # Make sure we didn't leave any lingering threads
    threads = running_threads
    thread_count = threads.size
    running_threads_str = threads.join("\n")
    #Thread.list.each {|thr| thr.kill if thr.status == 'sleep_forever'}
    expect(thread_count).to eql(1),
    "At end of test expect 1 remaining thread but found #{thread_count}.\nEnsure you kill all spawned threads before the test finishes.\nThreads:\n#{running_threads_str}"
  end
end

# Commented out for performance reasons
# If you want to manually profile, benchmark, or stress test then uncomment
# require 'ruby-prof' if RUBY_ENGINE == 'ruby'
# require 'benchmark/ips' if ENV.key?("BENCHMARK")
# RSpec.configure do |c|
#   if ENV.key?("PROFILE")
#     c.before(:suite) do
#       RubyProf.start
#     end
#     c.after(:suite) do |example|
#       result = RubyProf.stop
#       result.exclude_common_methods!
#       printer = RubyProf::GraphHtmlPrinter.new(result)
#       printer.print(File.open("profile.html", 'w+'), :min_percent => 1)
#     end
#     c.around(:each) do |example|
#       # Run each test 100 times to prevent startup issues from dominating
#       100.times do
#         example.run
#       end
#     end
#   end
#   if ENV.key?("BENCHMARK")
#     c.around(:each) do |example|
#       Benchmark.ips do |x|
#         x.report(example.metadata[:full_description]) do
#           example.run
#         end
#       end
#     end
#   end
#   if ENV.key?("STRESS")
#     c.around(:each) do |example|
#       begin
#         GC.stress = true
#         example.run
#       ensure
#         GC.stress = false
#       end
#     end
#   end
# # This code causes a new profile file to be created for each test case which is excessive and hard to read
# #  c.around(:each) do |example|
# #    if ENV.key?("PROFILE")
# #      klass = example.metadata[:example_group][:example_group][:description_args][0].to_s.gsub(/::/,'')
# #      method = example.metadata[:description_args][0].to_s.gsub!(/ /,'_')
# #      RubyProf.start
# #      100.times do
# #        example.run
# #      end
# #      result = RubyProf.stop
# #      result.eliminate_methods!([/RSpec/, /BasicObject/])
# #      printer = RubyProf::GraphHtmlPrinter.new(result)
# #      dir = "./profile/#{klass}"
# #      FileUtils.mkdir_p(dir)
# #      printer.print(File.open("#{dir}/#{method}.html", 'w+'), :min_percent => 2)
# #    else
# #      example.run
# #    end
# #  end
# end
