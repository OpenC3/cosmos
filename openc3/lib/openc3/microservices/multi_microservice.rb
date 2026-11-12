# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/microservices/microservice'
require 'openc3/topics/topic'
require 'openc3/utilities/thread_manager'
require 'openc3/utilities/sleeper'

module OpenC3
  # Runs other microservices as threads in one process. They are given on the
  # command line, or if none are given (as for a MICROSERVICE_GROUP's
  # MULTIGROUP) they are the microservices that name this one as their parent.
  class MultiMicroservice < Microservice
    def child_models
      names = ARGV.dup
      if names.empty?
        names = MicroserviceModel.all(scope: @scope).values.select { |config| config['parent'] == @name }.map { |config| config['name'] }.sort
      end
      names.map { |name| MicroserviceModel.get_model(name: name, scope: @scope) }.compact.select(&:enabled)
    end

    def run
      models = child_models()
      # System is one per process and the first microservice to set it up
      # decides which targets it has, so set it up for every child first
      target_names = models.map(&:target_names).flatten.compact.uniq
      System.setup_targets(target_names, @temp_dir, scope: @scope, descriptions: false)
      self.class.ensure_pool_sizes(models)

      models.each do |microservice_model|
        thread = Thread.new do
          cmd_line = microservice_model.cmd.join(' ')
          split_cmd_line = cmd_line.split(' ')
          filename = nil
          split_cmd_line.each do |item|
            if File.extname(item) == '.rb'
              filename = item
              break
            end
          end
          raise "Could not determine class filename from '#{cmd_line}'" unless filename

          OpenC3.set_working_dir(microservice_model.work_dir) do
            require File.join(microservice_model.work_dir, filename)
          end
          klass = filename.filename_to_class_name.to_class
          klass.run(microservice_model.name)
        end
        ThreadManager.instance.register(thread)
      end
      if models.empty?
        # Nothing to run until the operator restarts this with children
        @sleeper = Sleeper.new
        @sleeper.sleep(1) until @cancel_thread
      else
        ThreadManager.instance.monitor
        ThreadManager.instance.shutdown
      end
    end

    def shutdown
      @sleeper&.cancel
      super()
    end

    # Redis connections every child may use at once: one held while it reads
    # its topics and one for other calls
    CONNECTIONS_PER_CHILD = 2
    DEFAULT_POOL_SIZE = 100

    # The children share this process's Redis connection pools, which are sized
    # for one microservice. Each child holds a connection while it reads its
    # topics, so with too many children some can't get one in time and die.
    def self.ensure_pool_sizes(models)
      pool_size = DEFAULT_POOL_SIZE + (models.length * CONNECTIONS_PER_CHILD)
      db_shards = ([0] + models.map { |model| model.db_shard.to_i }).uniq
      db_shards.each do |db_shard|
        Store.instance(db_shard: db_shard).ensure_pool_size(pool_size)
        EphemeralStore.instance(db_shard: db_shard).ensure_pool_size(pool_size)
      end
    end
  end
end
if __FILE__ == $0
  OpenC3::MultiMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end
