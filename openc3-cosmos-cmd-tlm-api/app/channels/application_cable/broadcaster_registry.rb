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
  # Only entries that have sent at least one heartbeat are reaped. Older clients
  # (and the Ruby/Python scripting WebSocket APIs) never heartbeat, and a
  # realtime stream legitimately goes a long time with no client-to-server
  # traffic, so reaping them on idle time alone would kill healthy streams.
  class BroadcasterRegistry
    # Clients heartbeat every 60s, so this tolerates several missed heartbeats
    # (e.g. background tab timer throttling) before reaping
    DEFAULT_TTL = 300
    DEFAULT_SWEEP_INTERVAL = 60

    Entry = Struct.new(:broadcaster, :last_activity, :heartbeat)

    @entries = {}
    @mutex = Mutex.new
    @sweeper = nil

    class << self
      def ttl
        ENV.fetch('OPENC3_CABLE_SUBSCRIPTION_TTL', DEFAULT_TTL).to_f
      end

      def sweep_interval
        ENV.fetch('OPENC3_CABLE_SWEEP_INTERVAL', DEFAULT_SWEEP_INTERVAL).to_f
      end

      def register(key, broadcaster)
        previous = nil
        @mutex.synchronize do
          previous = @entries[key]&.broadcaster
          @entries[key] = Entry.new(broadcaster, now(), false)
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

      def unregister(key)
        entry = @mutex.synchronize { @entries.delete(key) }
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
        @mutex.synchronize { @entries.clear }
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
