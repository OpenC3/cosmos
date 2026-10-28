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

module ApplicationCable
  # Process-wide registry of the per-subscription broadcaster objects
  # (StreamingApi, MessagesApi, *EventsApi) that the channels create.
  #
  # Entries are normally removed by the channel's `unsubscribed`. Under AnyCable
  # that arrives as a separate Disconnect RPC from anycable-go, and if it is
  # never delivered (anycable-go restarting or crashing, the gRPC stream being
  # torn down) the broadcaster and its Redis-reading threads would live for the
  # rest of the process. To bound that, clients send a periodic `heartbeat`
  # perform and a background sweeper reaps any entry that has stopped
  # heartbeating for longer than TTL.
  #
  # Only entries registered as heartbeating (the client said it heartbeats when
  # it subscribed) or that have sent a heartbeat are reaped. Older clients (and
  # the Ruby/Python scripting WebSocket APIs) never heartbeat, and a realtime
  # stream legitimately goes a long time with no client-to-server traffic, so
  # reaping them on idle time alone would kill healthy streams.
  class BroadcasterRegistry
    # Clients heartbeat every 60s, so this tolerates several missed heartbeats
    # (e.g. background tab timer throttling) before reaping
    DEFAULT_TTL = 300
    DEFAULT_SWEEP_INTERVAL = 60
    # A ttl shorter than the client heartbeat interval would reap healthy
    # clients between heartbeats, so never go below two heartbeats
    MIN_TTL = 120
    # Keeps a zero or invalid interval from turning the sweeper into a busy loop
    MIN_SWEEP_INTERVAL = 1

    Entry = Struct.new(:broadcaster, :last_activity, :heartbeat, :token)

    @entries = {}
    @mutex = Mutex.new
    @sweeper = nil
    @clamp_warnings = {}

    class << self
      def ttl
        env_seconds('OPENC3_CABLE_SUBSCRIPTION_TTL', DEFAULT_TTL, MIN_TTL)
      end

      def sweep_interval
        env_seconds('OPENC3_CABLE_SWEEP_INTERVAL', DEFAULT_SWEEP_INTERVAL, MIN_SWEEP_INTERVAL)
      end

      # heartbeat: true makes the entry reapable immediately rather than only
      # after its first heartbeat, so a client that dies right after
      # subscribing is still reaped. token identifies this registration so a
      # late unregister from an older subscription can't remove a newer one.
      def register(key, broadcaster, heartbeat: false, token: nil)
        previous = nil
        @mutex.synchronize do
          previous = @entries[key]&.broadcaster
          @entries[key] = Entry.new(broadcaster, now(), heartbeat, token)
        end
        # A duplicate subscribe for the same key must not leak the old one
        kill(key, previous) if previous and !previous.equal?(broadcaster)
        start_sweeper()
        broadcaster
      end

      def get(key)
        @mutex.synchronize { @entries[key]&.broadcaster }
      end

      def registered?(key)
        @mutex.synchronize { @entries.key?(key) }
      end

      # Record client activity. Returns false if the key is not registered,
      # e.g. because it was already reaped.
      def touch(key, heartbeat: false)
        @mutex.synchronize do
          entry = @entries[key]
          return false unless entry
          entry.last_activity = now()
          entry.heartbeat = true if heartbeat
          return true
        end
      end

      # When token is given only the registration made with that token is
      # removed. Returns whether an entry was removed.
      def unregister(key, token: nil)
        entry = @mutex.synchronize do
          current = @entries[key]
          next nil unless current
          next nil if token and current.token != token
          @entries.delete(key)
        end
        kill(key, entry.broadcaster) if entry and entry.broadcaster
        !entry.nil?
      end

      # Remove and kill every heartbeating entry idle for longer than ttl.
      # Returns the reaped keys.
      def sweep(current_time = now())
        expired = []
        @mutex.synchronize do
          cutoff = current_time - ttl()
          @entries.each do |key, entry|
            expired << [key, entry] if entry.heartbeat and entry.last_activity < cutoff
          end
          expired.each { |key, _| @entries.delete(key) }
        end
        # Kill outside the lock as it may wait on the broadcaster's threads
        expired.each do |key, entry|
          OpenC3::Logger.warn("Reaping cable subscription #{key}: no heartbeat in #{(current_time - entry.last_activity).round}s")
          kill(key, entry.broadcaster) if entry.broadcaster
        end
        expired.map(&:first)
      end

      def size
        @mutex.synchronize { @entries.length }
      end

      # For tests
      def clear
        @mutex.synchronize do
          @entries.clear
          @clamp_warnings.clear
        end
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def env_seconds(name, default, minimum)
        raw = ENV.fetch(name, nil)
        return default.to_f if raw.nil? or raw.to_s.strip.empty?
        value = Float(raw, exception: false)
        return value if value and value >= minimum
        fallback = value ? minimum.to_f : default.to_f
        # Only warn once per value, ttl is read on every sweep
        unless @clamp_warnings[name] == raw
          @clamp_warnings[name] = raw
          OpenC3::Logger.warn("#{name}=#{raw} is invalid or below the minimum of #{minimum}s, using #{fallback}s")
        end
        fallback
      end

      def kill(key, broadcaster)
        broadcaster.kill
      rescue => e
        OpenC3::Logger.error("Error killing cable subscription #{key}: #{e.formatted}")
      end

      def start_sweeper
        return if @sweeper&.alive?
        @mutex.synchronize do
          return if @sweeper&.alive?
          @sweeper = Thread.new do
            loop do
              sleep(sweep_interval())
              begin
                sweep()
              rescue => e
                OpenC3::Logger.error("Cable subscription sweeper error: #{e.formatted}")
              end
            end
          end
        end
      end
    end
  end
end
