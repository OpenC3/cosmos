# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'redis'
require 'hiredis-client'
require 'json'
require 'connection_pool'

module OpenC3
  class StoreConnectionPool < ConnectionPool
    def pipelined
      with do |redis|
        redis.pipelined do |pipeline|
          Thread.current[:pipeline] = pipeline
          begin
            yield
          ensure
            Thread.current[:pipeline] = nil
          end
        end
      end
    end

    def with(**options, &block)
      pipeline = Thread.current[:pipeline]
      if pipeline
        yield pipeline
      else
        super(**options, &block)
      end
    end
  end

  class Store
    # Variable that holds the singleton instances per db_shard
    @instances = []

    # DB_Shard cache: { "scope__target_name" => [db_shard_number, Time] }
    @@db_shard_cache = {}
    @@db_shard_cache_mutex = Mutex.new
    DB_SHARD_CACHE_TIMEOUT = 60 # seconds

    # Mutex used to ensure that only one instance is created
    @@instance_mutex = Mutex.new

    attr_reader :redis_url
    attr_reader :redis_pool

    # Look up the db_shard number for a target with a 1-minute cache.
    # Reads directly from Redis db_shard 0 to avoid circular deps with TargetModel.
    # Non-target-specific data (nil target_name) always returns db_shard 0.
    def self.db_shard_for_target(target_name, scope: "DEFAULT")
      return 0 unless target_name

      cache_key = "#{scope}__#{target_name}"
      now = Time.now

      @@db_shard_cache_mutex.synchronize do
        cached = @@db_shard_cache[cache_key]
        if cached
          db_shard, cached_at = cached
          return db_shard if (now - cached_at) < DB_SHARD_CACHE_TIMEOUT
        end
      end

      begin
        json = Store.instance(db_shard: 0).hget("#{scope}__openc3_targets", target_name)
        db_shard = json ? JSON.parse(json)['db_shard'].to_i : 0
      rescue
        db_shard = 0
      end

      @@db_shard_cache_mutex.synchronize do
        @@db_shard_cache[cache_key] = [db_shard, now]
      end

      db_shard
    end

    # Get the singleton instance
    def self.instance(pool_size = 100, db_shard: 0)
      # Logger.level = Logger::DEBUG
      @instances ||= []
      the_instance = @instances[db_shard]
      return the_instance if the_instance

      @@instance_mutex.synchronize do
        @instances ||= []
        @instances[db_shard] ||= self.new(pool_size, db_shard: db_shard)
        return @instances[db_shard]
      end
    end

    # Delegate all unknown class methods to delegate to the instance
    def self.method_missing(message, *args, **kwargs, &block)
      self.instance.public_send(message, *args, **kwargs, &block)
    end

    # Delegate all unknown methods to redis through the @redis_pool
    def method_missing(message, *args, **kwargs, &block)
      @redis_pool.with { |redis| redis.public_send(message, *args, **kwargs, &block) }
    end

    def initialize(pool_size = 10, db_shard: 0)
      @redis_username = ENV['OPENC3_REDIS_USERNAME']
      @redis_key = ENV['OPENC3_REDIS_PASSWORD']
      hostname = ENV['OPENC3_REDIS_HOSTNAME'].to_s.gsub("SHARDNUM", db_shard.to_s)
      @redis_url = "redis://#{hostname}:#{ENV.fetch('OPENC3_REDIS_PORT', 6379)}"
      @redis_pool = StoreConnectionPool.new(size: pool_size) { build_redis() }
    end

    def build_redis
      return Redis.new(url: @redis_url, username: @redis_username, password: @redis_key)
    end

    ###########################################################################
    # Stream APIs
    ###########################################################################

    def get_oldest_message(topic)
      @redis_pool.with do |redis|
        result = redis.xrange(topic, count: 1)
        if result and result.length > 0
          return result[0]
        else
          return nil
        end
      end
    end

    def get_newest_message(topic)
      @redis_pool.with do |redis|
        # Default in xrevrange is range end '+', start '-' which means get all
        # elements from higher ID to lower ID and since we're limiting to 1
        # we get the last element. See https://redis.io/commands/xrevrange.
        result = redis.xrevrange(topic, count: 1)
        if result and result.length > 0
          return result[0]
        else
          return nil
        end
      end
    end

    def get_last_offset(topic)
      @redis_pool.with do |redis|
        result = redis.xrevrange(topic, count: 1)
        if result and result[0] and result[0][0]
          result[0][0]
        else
          "0-0"
        end
      end
    end

    def update_topic_offsets(topics)
      offsets = []
      topics.each do |topic|
        # Normally we will just be grabbing the topic offset
        # this allows xread to get everything past this point
        Thread.current[:topic_offsets] ||= {}
        topic_offsets = Thread.current[:topic_offsets]
        last_id = topic_offsets[topic]
        if last_id
          offsets << last_id
        else
          # If there is no topic offset this is the first call.
          # Get the last offset ID so we'll start getting everything from now on
          offsets << get_last_offset(topic)
          topic_offsets[topic] = offsets[-1]
        end
      end
      return offsets
    end

    def read_topics(topics, offsets = nil, timeout_ms = 1000, count = nil)
      return {} if topics.empty?
      Thread.current[:topic_offsets] ||= {}
      topic_offsets = Thread.current[:topic_offsets]
      begin
        # Logger.debug "read_topics: #{topics}, #{offsets} pool:#{@redis_pool}"
        @redis_pool.with do |redis|
          offsets = update_topic_offsets(topics) unless offsets
          result = redis.xread(topics, offsets, block: timeout_ms, count: count)
          if result and result.length > 0
            result.each do |topic, messages|
              messages.each do |msg_id, msg_hash|
                topic_offsets[topic] = msg_id
                yield topic, msg_id, msg_hash, redis if block_given?
              end
            end
          end
          # Logger.debug "result:#{result}" if result and result.length > 0
          return result
        end
      rescue Redis::TimeoutError
        return {} # Should return an empty hash not array - xread returns a hash
      end
    end

    # Add new entry to the redis stream.
    # > https://www.rubydoc.info/github/redis/redis-rb/Redis:xadd
    #
    # @example Without options
    #   store.write_topic('MANGO__TOPIC', {'message' => 'something'})
    # @example With options
    #   store.write_topic('MANGO__TOPIC', {'message' => 'something'}, id: '0-0', maxlen: 1000, approximate: 'true')
    #
    # @param topic [String] the stream / topic
    # @param msg_hash [Hash]   one or multiple field-value pairs
    #
    # @option opts [String]  :id          the entry id, default value is `*`, it means auto generation,
    #   if `nil` id is passed it will be changed to `*`
    # @option opts [Integer] :maxlen      max length of entries, default value is `nil`, it means will grow forever
    # @option opts [String] :approximate whether to add `~` modifier of maxlen or not, default value is 'true'
    #
    # @return [String] the entry id
    def write_topic(topic, msg_hash, id = '*', maxlen = nil, approximate = 'true')
      id = '*' if id.nil?
      @redis_pool.with do |redis|
        return redis.xadd(topic, msg_hash, id: id, maxlen: maxlen, approximate: approximate)
      end
    end

    # Trims older entries of the redis stream if needed.
    # > https://www.rubydoc.info/github/redis/redis-rb/Redis:xtrim
    #
    # @example Without options
    #   store.trim_topic('MANGO__TOPIC', 1000)
    # @example With options
    #   store.trim_topic('MANGO__TOPIC', 1000, approximate: 'true', limit: 0)
    #
    # @param topic  [String]  the stream key
    # @param minid  [Integer] Id to throw away data up to
    # @param approximate [Boolean] whether to add `~` modifier of maxlen or not
    # @param limit  [Boolean] number of items to return from the call
    #
    # @return [Integer] the number of entries actually deleted
    def trim_topic(topic, minid, approximate = true, limit: 0)
      @redis_pool.with do |redis|
        return redis.xtrim_minid(topic, minid, approximate: approximate, limit: limit)
      end
    end
  end

  class EphemeralStore < Store
    def initialize(pool_size = 10, db_shard: 0)
      super(pool_size)
      hostname = ENV['OPENC3_REDIS_EPHEMERAL_HOSTNAME'].to_s.gsub("SHARDNUM", db_shard.to_s)
      @redis_url = "redis://#{hostname}:#{ENV.fetch('OPENC3_REDIS_EPHEMERAL_PORT', 6380)}"
      @redis_pool = StoreConnectionPool.new(size: pool_size) { build_redis() }
    end
  end
end

class Redis
  def xtrim_minid(key, minid, approximate: true, limit: nil)
    args = [:xtrim, key, :MINID, (approximate ? '~' : '='), minid]
    args.concat([:LIMIT, limit]) if limit
    send_command(args)
  end
end
