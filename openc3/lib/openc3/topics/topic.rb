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

require 'openc3/utilities/store'
require 'openc3/utilities/logger'

module OpenC3
  class Topic
    # Stream trimming contract for the high rate target streams
    # (TELEMETRY__, COMMAND__, DECOM__, DECOMCMD__):
    #
    # The streams are primarily trimmed by their consumers once the data is safely
    # persisted elsewhere:
    #   * TELEMETRY__ / COMMAND__ are trimmed by the log microservice (LogWriter) once a
    #     log file has been moved to the bucket plus LogWriter::CLEANUP_DELAY.
    #   * DECOM__ / DECOMCMD__ are trimmed by the TSDB microservice which keeps
    #     TsdbMicroservice::TRIM_KEEP_MS of data behind what it has read.
    #
    # If a trimmer is absent (logging disabled, no TSDB) or falls far behind, the streams
    # would grow without bound. As a safety net every write to these streams also passes
    # an approximate XADD MINID so no entry older than the safety max age is retained.
    # The max age is OPENC3_STREAM_MAX_AGE_SECONDS (default 600s, 0 or empty disables) and is
    # never less than STREAM_MAX_AGE_MIN_SECONDS. For TELEMETRY__ / COMMAND__ the max age is
    # never less than two log cycles plus the cleanup delay, because historical streaming reads
    # data not yet in the bucket from the stream.
    #
    # When the minid is calculated from now (auto generated ids) it uses this host's clock while
    # Redis generates the ids from its own clock. A writer clock ahead of Redis by more than the
    # max age would trim the entire stream (including the entry being added) so hosts must be
    # time synchronized (NTP).
    STREAM_MAX_AGE_DEFAULT_SECONDS = 600
    # Twice TsdbMicroservice::TRIM_KEEP_MS. Also protects against small clock offsets.
    STREAM_MAX_AGE_MIN_SECONDS = 120
    # LogWriter::CLEANUP_DELAY is defined from this
    LOG_CLEANUP_DELAY_SECONDS = 60
    # TargetModel default log cycle time
    DEFAULT_LOG_CYCLE_TIME_SECONDS = 600
    # How long to wait before retrying a failed log cycle time lookup
    LOG_CYCLE_LOOKUP_RETRY_SECONDS = 60
    # These are calculated on the write path of every packet so they are cached per process.
    # The environment doesn't change while a microservice runs and the log cycle time only
    # changes when the plugin (and therefore the microservices) are reinstalled.
    @@stream_max_age_ms = nil
    @@log_stream_max_age_ms = {}
    @@log_cycle_lookup_retry_at = {}

    # Delegate all unknown class methods to EphemeralStore db_shard 0 (system-level topics)
    def self.method_missing(message, *args, **kwargs, &block)
      EphemeralStore.public_send(message, *args, **kwargs, &block)
    end

    def self.clear_topics(topics, maxlen = 0, db_shard: 0)
      store = EphemeralStore.instance(db_shard: db_shard)
      topics.each { |topic| store.xtrim(topic, maxlen) }
    end

    def self.get_cnt(topic, db_shard: 0)
      _, packet = EphemeralStore.instance(db_shard: db_shard).get_newest_message(topic)
      packet ? packet["received_count"].to_i : 0
    end

    # DB_Shard-aware topic methods for target-specific streams.
    # These explicitly route to the correct EphemeralStore db_shard.

    def self.write_topic(topic, msg_hash, id = '*', maxlen = nil, approximate = 'true', minid: nil, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).write_topic(topic, msg_hash, id, maxlen, approximate, minid: minid)
    end

    # @return [Float] Configured safety max age in seconds (<= 0 means disabled)
    def self.stream_max_age_seconds
      value = ENV.fetch('OPENC3_STREAM_MAX_AGE_SECONDS', nil)
      return STREAM_MAX_AGE_DEFAULT_SECONDS if value.nil?
      return 0.0 if value.strip.empty?
      # Strictly parse and reject nan / inf, which would raise when converted to
      # milliseconds on every write. A typo keeps the safety cap at the default
      # rather than disabling it.
      seconds = Float(value, exception: false)
      return seconds if seconds&.finite?
      Logger.warn("OPENC3_STREAM_MAX_AGE_SECONDS of '#{value}' is invalid, using #{STREAM_MAX_AGE_DEFAULT_SECONDS}")
      return STREAM_MAX_AGE_DEFAULT_SECONDS
    end

    # @return [Integer] Cached safety max age in milliseconds (0 means disabled)
    def self.stream_max_age_ms
      @@stream_max_age_ms ||= begin
        seconds = stream_max_age_seconds
        if seconds <= 0
          0
        elsif seconds < STREAM_MAX_AGE_MIN_SECONDS
          Logger.warn("OPENC3_STREAM_MAX_AGE_SECONDS of #{seconds} is below the minimum, using #{STREAM_MAX_AGE_MIN_SECONDS}")
          STREAM_MAX_AGE_MIN_SECONDS * 1000
        else
          (seconds * 1000).to_i
        end
      end
    end

    # Calculates the MINID to pass to XADD to cap the age of entries in a target stream.
    # The cap is anchored to the id being written (or now for auto generated ids) so an
    # explicitly id'd entry (e.g. decom reusing the raw packet id) is never trimmed by its own add.
    #
    # @param id [String] The id being written ('*' or nil for auto generation)
    # @param max_age_ms [Integer] Max age to retain (<= 0 means disabled)
    # @return [String|nil] The minid or nil if the safety cap is disabled
    def self.stream_safety_minid(id = '*', max_age_ms: stream_max_age_ms)
      return nil if max_age_ms <= 0
      if id.nil? or id == '*'
        base_ms = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
      else
        base_ms = id.to_s.to_i # Stops at the '-' sequence separator
      end
      minid_ms = base_ms - max_age_ms
      return nil if minid_ms <= 0
      return minid_ms.to_s
    end

    # Calculates the MINID for a TELEMETRY__ / COMMAND__ stream write which also never
    # trims younger than log_stream_min_age_seconds. The resulting max age is cached per stream.
    #
    # @param target_name [String] Target name
    # @param cmd_or_tlm [Symbol] :CMD or :TLM
    # @return [String|nil] The minid or nil if the safety cap is disabled
    def self.log_stream_safety_minid(target_name, cmd_or_tlm, scope:)
      target_cache = ((@@log_stream_max_age_ms[scope] ||= {})[target_name] ||= {})
      max_age_ms = target_cache[cmd_or_tlm]
      unless max_age_ms
        max_age_ms = log_stream_max_age_ms(target_name, cmd_or_tlm, scope: scope)
        return nil unless max_age_ms # Log cycle time unknown so don't cap yet
        target_cache[cmd_or_tlm] = max_age_ms
      end
      return stream_safety_minid(max_age_ms: max_age_ms)
    end

    # @param target_name [String] Target name
    # @param cmd_or_tlm [Symbol] :CMD or :TLM
    # @return [Integer|nil] Max age in milliseconds for a TELEMETRY__ / COMMAND__ stream (0 means
    #   disabled) or nil if the log cycle time couldn't be determined. Guessing the log cycle time
    #   could trim data historical streaming still needs, so the stream isn't capped until a
    #   lookup (retried every LOG_CYCLE_LOOKUP_RETRY_SECONDS) succeeds.
    def self.log_stream_max_age_ms(target_name, cmd_or_tlm, scope:)
      max_age_ms = stream_max_age_ms
      return max_age_ms if max_age_ms <= 0
      key = [scope, target_name, cmd_or_tlm]
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      retry_at = @@log_cycle_lookup_retry_at[key]
      return nil if retry_at and now < retry_at
      begin
        min_age_ms = log_stream_min_age_seconds(target_name, cmd_or_tlm, scope: scope) * 1000
      rescue => e
        Logger.warn("Unable to determine log cycle time for #{target_name} #{cmd_or_tlm}, stream age not capped: #{e.message}")
        @@log_cycle_lookup_retry_at[key] = now + LOG_CYCLE_LOOKUP_RETRY_SECONDS
        return nil
      end
      @@log_cycle_lookup_retry_at.delete(key)
      return [max_age_ms, min_age_ms].max
    end

    # Minimum age to retain in a TELEMETRY__ / COMMAND__ stream so the log microservice
    # and historical streaming always have the data not yet moved to the bucket.
    #
    # @param target_name [String] Target name
    # @param cmd_or_tlm [Symbol] :CMD or :TLM
    # @return [Integer] Minimum age in seconds
    # @raise If the TargetModel lookup fails
    def self.log_stream_min_age_seconds(target_name, cmd_or_tlm, scope:)
      require 'openc3/models/target_model'
      cycle_time = DEFAULT_LOG_CYCLE_TIME_SECONDS
      model = TargetModel.get(name: target_name, scope: scope)
      if model
        value = model[cmd_or_tlm == :CMD ? 'cmd_log_cycle_time' : 'tlm_log_cycle_time'].to_i
        cycle_time = value if value > 0
      end
      return 2 * (cycle_time + LOG_CLEANUP_DELAY_SECONDS)
    end

    def self.clear_stream_max_age_cache
      @@stream_max_age_ms = nil
      @@log_stream_max_age_ms = {}
      @@log_cycle_lookup_retry_at = {}
    end

    def self.read_topics(topics, offsets = nil, timeout_ms = 1000, count = nil, db_shard: 0, &block)
      EphemeralStore.instance(db_shard: db_shard).read_topics(topics, offsets, timeout_ms, count, &block)
    end

    def self.get_newest_message(topic, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).get_newest_message(topic)
    end

    def self.get_oldest_message(topic, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).get_oldest_message(topic)
    end

    def self.get_last_offset(topic, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).get_last_offset(topic)
    end

    def self.update_topic_offsets(topics, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).update_topic_offsets(topics)
    end

    def self.trim_topic(topic, minid, approximate = true, limit: 0, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).trim_topic(topic, minid, approximate, limit: limit)
    end

    def self.del(topic, db_shard: 0)
      EphemeralStore.instance(db_shard: db_shard).del(topic)
    end

    # Group topics by db_shard. Each topic's target name is extracted and looked up.
    # Topics matching target_pattern are db_sharded; others go to db_shard 0.
    # @param topics [Array<String>] List of topic strings
    # @param target_pattern [String] Substring to identify target-specific topics (e.g. 'CMD}TARGET__', '__TELEMETRY__')
    # @param scope [String] Scope name for db_shard lookup
    # @return [Hash] { db_shard => [topic, ...] }
    def self.group_topics_by_db_shard(topics, target_pattern:, scope:)
      groups = {}
      topics.each do |topic|
        if topic.include?(target_pattern)
          target_name = topic.match(/__\{?([^}_]+)\}?__/)[1] rescue nil
          # Handle CMD}TARGET__ pattern where target is after TARGET__
          target_name = topic.split('TARGET__')[1] if target_pattern.include?('TARGET__') && target_name.nil?
          db_shard = (Store.db_shard_for_target(target_name, scope: scope) || 0).to_i
        else
          db_shard = 0
        end
        groups[db_shard] ||= []
        groups[db_shard] << topic
      end
      groups
    end

    # Check if all db_shard groups resolve to a single db_shard (fast path).
    def self.all_same_db_shard?(db_shard_groups)
      db_shard_groups.length <= 1
    end

    # Build the ACK topic from a command/router topic and write the ack.
    def self.write_ack(topic, result, msg_id, db_shard: 0)
      ack_topic = topic.split("__")
      ack_topic[1] = 'ACK' + ack_topic[1]
      ack_topic = ack_topic.join("__")
      Topic.write_topic(ack_topic, { 'result' => result, 'id' => msg_id }, '*', 100, db_shard: db_shard)
    end
  end
end
