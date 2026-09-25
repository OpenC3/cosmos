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

require 'openc3/top_level'
require 'openc3/core_ext/exception'
require 'openc3/utilities/logger'

module OpenC3
  # Mixin which reads an underlying socket / stream in a dedicated thread and
  # buffers the results on a queue. This keeps the operating system receive
  # buffers drained as fast as possible so data isn't dropped while the packet
  # reading thread is busy processing protocols and writing to the database.
  #
  # Classes which include this module must implement read_queue_data which
  # performs a single blocking read and returns the data read or nil to
  # indicate the read source is done (which disconnects the interface).
  module ReadQueue
    # Maximum number of bytes buffered on the queue before the read thread
    # blocks and lets the operating system do the buffering instead
    DEFAULT_READ_QUEUE_MAX_SIZE = 100 * 1024 * 1024 # 100MB

    # Approximate memory each queued read costs on top of the data itself (the
    # String object plus the queue entry). Small reads are dominated by this so
    # it is charged against the budget, otherwise a stream delivering a few
    # bytes at a time would hold many times the budget in actual memory.
    READ_QUEUE_ENTRY_OVERHEAD = 64

    # How long to wait before re-checking whether the interface has been
    # disconnected while blocked waiting for room on the queue
    QUEUE_POLL_TIMEOUT = 0.1

    # How long to wait for the read thread to exit when disconnecting
    THREAD_JOIN_TIMEOUT = 2

    # @return [Integer] Maximum number of bytes buffered on the queue
    attr_reader :read_queue_max_size

    # Initialize the read queue attributes. Must be called from the including
    # class initialize method.
    def initialize_read_queue(max_size = DEFAULT_READ_QUEUE_MAX_SIZE)
      @raw_read_queue = nil
      @raw_read_thread = nil
      @raw_read_cancel = false
      @raw_read_bytes = 0
      @raw_read_budget = 0
      # Guards @raw_read_bytes / @raw_read_budget and wakes the read thread when
      # the bytes it queued are consumed and there is room to queue more
      @raw_read_mutex = Mutex.new
      @raw_read_condition = ConditionVariable.new
      @read_queue_max_size = max_size
    end

    # Supported Options
    # READ_QUEUE_MAX_SIZE - Maximum number of bytes buffered on the read queue
    # (see Interface#set_option)
    def set_option(option_name, option_values)
      super(option_name, option_values)
      if option_name.upcase == 'READ_QUEUE_MAX_SIZE'
        max_size = Integer(option_values[0])
        raise "READ_QUEUE_MAX_SIZE must be a positive integer but was #{max_size}" if max_size < 1

        @read_queue_max_size = max_size
      end
    end

    # @return [Integer] The number of reads waiting on the read queue
    def read_queue_size
      queue = @raw_read_queue
      queue ? queue.size : 0
    end

    # @return [Integer] The number of bytes waiting on the read queue
    def read_queue_bytes
      return 0 unless @raw_read_queue

      @raw_read_mutex.synchronize { @raw_read_bytes }
    end

    # Perform a single blocking read. Must be implemented by the including class.
    #
    # @return [String, nil] Data read or nil if the read source is done
    def read_queue_data
      raise "read_queue_data not defined by #{self.class}"
    end

    # Start the thread which continuously reads and queues data
    def start_read_queue_thread
      stop_read_queue_thread()
      queue = Queue.new
      @raw_read_mutex.synchronize do
        @raw_read_cancel = false
        @raw_read_bytes = 0
        @raw_read_budget = 0
      end
      @raw_read_queue = queue
      @raw_read_thread = Thread.new do
        read_queue_thread_body(queue)
      rescue Exception => e
        Logger.error "#{@name}: Read queue thread unexpectedly died: #{e.formatted}"
      end
    end

    # Stop the read thread and discard anything left on the queue. The read
    # source should be disconnected first so the thread isn't blocked reading.
    def stop_read_queue_thread
      queue = @raw_read_queue
      @raw_read_queue = nil
      @raw_read_mutex.synchronize do
        @raw_read_cancel = true
        @raw_read_bytes = 0
        @raw_read_budget = 0
        # Unblock the read thread if it is waiting for room on the queue
        @raw_read_condition.broadcast
      end
      # Closing the queue unblocks read_queue_pop
      queue.close if queue
      thread = @raw_read_thread
      @raw_read_thread = nil
      # The read source should already be disconnected which unblocks the read
      if thread and thread != Thread.current and !thread.join(THREAD_JOIN_TIMEOUT)
        OpenC3.kill_thread(nil, thread)
      end
    end

    # Retrieve the next data off the read queue, blocking until it is available.
    #
    # @return [String, nil] Data read or nil if the read source is done
    def read_queue_pop
      queue = @raw_read_queue
      unless queue
        # The read thread is normally started by connect but interfaces can also
        # be handed an already connected stream so start it on demand
        start_read_queue_thread() if connected?
        queue = @raw_read_queue
        return nil unless queue
      end

      data = queue.pop
      if data.kind_of?(String)
        @raw_read_mutex.synchronize do
          @raw_read_bytes -= data.length
          @raw_read_budget -= data.length + READ_QUEUE_ENTRY_OVERHEAD
          # Tell the read thread there is room for more data
          @raw_read_condition.broadcast
        end
      end
      # Exceptions raised by the read thread are re-raised here so they are
      # handled exactly as they were when the read happened inline
      raise data if data.kind_of?(Exception)

      return data
    end

    # protected

    def read_queue_thread_body(queue)
      loop do
        begin
          data = read_queue_data()
        rescue Exception => e
          queue.push(e)
          break
        end
        # nil means the read source is done so tell read_queue_pop to disconnect
        if data.nil?
          queue.push(nil)
          break
        end
        # Charge the bytes against the budget before the push so
        # read_queue_bytes never goes negative if the data is dequeued
        # before we get back here
        break unless reserve_read_queue_bytes(data.length)

        queue.push(data)
      end
    rescue ClosedQueueError
      # Interface disconnected while we were pushing
    ensure
      # Closing tells read_queue_pop there will never be more data so it
      # returns nil rather than blocking forever
      queue.close
    end

    # Wait until the data fits in the byte budget and charge it against the
    # budget. A read larger than the entire budget is queued on its own rather
    # than never fitting, so the budget can be exceeded by at most one read.
    #
    # @return [Boolean] Whether the bytes were reserved (false if disconnected)
    def reserve_read_queue_bytes(length)
      cost = length + READ_QUEUE_ENTRY_OVERHEAD
      @raw_read_mutex.synchronize do
        while @raw_read_budget > 0 and (@raw_read_budget + cost) > @read_queue_max_size
          return false if @raw_read_cancel

          @raw_read_condition.wait(@raw_read_mutex, QUEUE_POLL_TIMEOUT)
        end
        return false if @raw_read_cancel

        @raw_read_bytes += length
        @raw_read_budget += cost
      end
      return true
    end
  end
end
