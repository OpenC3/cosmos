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

require 'timeout' # For Timeout::Error
require 'openc3/interfaces/interface'
require 'openc3/core_ext/exception'
require 'openc3/core_ext/time'
require 'openc3/utilities/logger'

module OpenC3
  # Interface base class which reads an underlying socket / stream (the reader)
  # in a dedicated thread and buffers the results on a queue. This keeps the
  # operating system receive buffers drained as fast as possible so data isn't
  # dropped while the packet reading thread is busy processing protocols and
  # writing to the database.
  #
  # Subclasses call start_read_queue_thread with the object they read from
  # (anything with a read method) once it is connected and stop_read_queue_thread
  # once it is disconnected. While the thread is running the reader's read
  # method is redirected to the queue, so the subclass (and anything else such
  # as derived classes or protocols) keeps calling reader.read exactly as before
  # and receives the data in the order it was read rather than competing with
  # the read thread for it.
  #
  # Setting READ_QUEUE_MAX_SIZE to 0 disables the read thread so the reader is
  # read inline, which is how interfaces read before the queue existed.
  class ReadQueueInterface < Interface
    # Maximum number of bytes buffered on the queue before the read thread
    # blocks and lets the operating system do the buffering instead
    DEFAULT_READ_QUEUE_MAX_SIZE = 20 * 1024 * 1024 # 20MB

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
    attr_accessor :read_queue_max_size

    # @return [Time, nil] When the read thread read the data most recently
    #   returned by the reader (nil when the read queue is disabled)
    attr_reader :read_queue_data_time

    def initialize
      super()
      initialize_read_queue()
    end

    # Initialize (or reset) the read queue attributes. Called by initialize.
    def initialize_read_queue(max_size = DEFAULT_READ_QUEUE_MAX_SIZE)
      @raw_read_queue = nil
      @raw_read_thread = nil
      @raw_reader = nil
      @raw_reader_read = nil
      @raw_read_bytes = 0
      @raw_read_budget = 0
      @raw_read_timeout_queued = false
      @read_queue_data_time = nil
      # Guards @raw_read_queue / @raw_read_bytes / @raw_read_budget and wakes the
      # read thread when the bytes it queued are consumed and there is room to
      # queue more. Each read thread is cancelled by closing its own queue under
      # this mutex, so a thread which outlives stop_read_queue_thread (and a new
      # thread starting) keeps seeing its old queue closed and can never touch
      # the byte counters or read again.
      @raw_read_mutex = Mutex.new
      @raw_read_condition = ConditionVariable.new
      @read_queue_max_size = max_size
    end

    # Supported Options
    # READ_QUEUE_MAX_SIZE - Maximum number of bytes buffered on the read queue
    #   or 0 to disable the read thread and read inline (see Interface#set_option)
    def set_option(option_name, option_values)
      super(option_name, option_values)
      if option_name.upcase == 'READ_QUEUE_MAX_SIZE'
        max_size = Integer(option_values[0])
        raise "READ_QUEUE_MAX_SIZE must be 0 (disabled) or a positive integer but was #{max_size}" if max_size < 0

        @read_queue_max_size = max_size
      end
    end

    # @return [Boolean] Whether reads are buffered by a read thread (false when
    #   READ_QUEUE_MAX_SIZE is 0 and reads happen inline)
    def read_queue_enabled?
      @read_queue_max_size > 0
    end

    # @return [Boolean] Whether a read thread has been started (and not stopped)
    def read_queue_started?
      !@raw_read_queue.nil?
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

    # Start the thread which continuously reads and queues data from the reader
    # and redirect the reader's read method to the queue. Does nothing beyond
    # stopping any existing thread if the read queue is disabled.
    #
    # @param reader [#read] Object to read from, e.g. a Stream or socket
    # @param read_args [Array] Arguments the read thread passes to reader.read.
    #   Arguments passed to the redirected read are ignored.
    def start_read_queue_thread(reader, *read_args)
      stop_read_queue_thread()
      return unless read_queue_enabled?

      queue = Queue.new
      @raw_read_mutex.synchronize do
        @raw_read_bytes = 0
        @raw_read_budget = 0
        @raw_read_timeout_queued = false
        @raw_read_queue = queue
      end
      begin
        raw_read = redirect_reader(reader)
      rescue FrozenError, TypeError
        Logger.warn "#{@name}: Can't redirect #{reader.class}#read so disabling the read queue"
        @raw_read_mutex.synchronize { @raw_read_queue = nil }
        @read_queue_max_size = 0
        return
      end
      @raw_read_thread = Thread.new do
        read_queue_thread_body(queue, raw_read, read_args)
      rescue Exception => e
        Logger.error "#{@name}: Read queue thread unexpectedly died: #{e.formatted}"
      end
    end

    # Stop the read thread, restore the reader's read method and discard anything
    # left on the queue. The reader should be disconnected first so the thread
    # isn't blocked reading.
    def stop_read_queue_thread
      # Allow subclasses to set their reader before initialize_read_queue
      return unless @raw_read_mutex

      @raw_read_mutex.synchronize do
        # Closing the queue under the mutex cancels the read thread (it either
        # already charged its bytes, which are reset below, or never will) and
        # unblocks read_queue_pop
        @raw_read_queue.close if @raw_read_queue
        @raw_read_queue = nil
        @raw_read_bytes = 0
        @raw_read_budget = 0
        @raw_read_timeout_queued = false
        @read_queue_data_time = nil
        # Unblock the read thread if it is waiting for room on the queue
        @raw_read_condition.broadcast
      end
      restore_reader()
      thread = @raw_read_thread
      @raw_read_thread = nil
      # The read source should already be disconnected which unblocks the read
      if thread and thread != Thread.current and !thread.join(THREAD_JOIN_TIMEOUT)
        OpenC3.kill_thread(nil, thread)
      end
    end

    # Retrieve the next data off the read queue, blocking until it is available.
    # This is what the reader's read method returns while it is redirected.
    #
    # @return [String, nil] Data read or nil if the read source is done
    def read_queue_pop
      queue = @raw_read_queue
      return nil unless queue

      loop do
        data = queue.pop
        if data.kind_of?(Array)
          data, time = data
          @raw_read_mutex.synchronize do
            # Counters were reset if the queue was stopped / replaced
            if queue.equal?(@raw_read_queue)
              @raw_read_bytes -= data.length
              @raw_read_budget -= data.length + READ_QUEUE_ENTRY_OVERHEAD
              @read_queue_data_time = time
              # Tell the read thread there is room for more data
              @raw_read_condition.broadcast
            end
          end
          return data
        end

        if data.kind_of?(Timeout::Error)
          @raw_read_mutex.synchronize { @raw_read_timeout_queued = false if queue.equal?(@raw_read_queue) }
          # Data queued behind the timeout arrived while nobody was waiting on
          # it, so an inline read would have returned it rather than timing out
          next unless queue.empty?
        end
        # Exceptions raised by the read thread are re-raised here so they are
        # handled exactly as they were when the read happened inline
        raise data if data.kind_of?(Exception)

        return data
      end
    end

    # @param data [String, nil] Data returned by reader.read
    # @return [Boolean] Whether the data indicates the reader is done (closed) so
    #   the read thread should stop. Subclasses can override this.
    def read_queue_done?(data)
      data.nil? or data.length <= 0
    end

    # protected

    def read_queue_thread_body(queue, raw_read, read_args)
      until queue.closed?
        begin
          data = raw_read.call(*read_args)
          data_time = Time.now.sys
        rescue Timeout::Error => e
          # A read timeout doesn't end the reader so pass it along and keep
          # reading. Only one is queued at a time so a reader which times out
          # quickly can't fill the queue with them.
          queue_timeout = @raw_read_mutex.synchronize do
            next false if queue.closed? or @raw_read_timeout_queued

            @raw_read_timeout_queued = true
          end
          queue.push(e) if queue_timeout
          next
        rescue Exception => e
          queue.push(e)
          break
        end
        # Tell whoever reads next that the reader is done and stop reading
        if read_queue_done?(data)
          queue.push(data)
          break
        end
        # Charge the bytes against the budget before the push so
        # read_queue_bytes never goes negative if the data is dequeued
        # before we get back here
        break unless reserve_read_queue_bytes(queue, data.length)

        # Queue the time of the read so packets are timestamped when the data
        # arrived rather than when it was processed
        queue.push([data, data_time])
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
    def reserve_read_queue_bytes(queue, length)
      cost = length + READ_QUEUE_ENTRY_OVERHEAD
      @raw_read_mutex.synchronize do
        while @raw_read_budget > 0 and (@raw_read_budget + cost) > @read_queue_max_size
          return false if queue.closed?

          @raw_read_condition.wait(@raw_read_mutex, QUEUE_POLL_TIMEOUT)
        end
        return false if queue.closed?

        @raw_read_bytes += length
        @raw_read_budget += cost
      end
      return true
    end

    # Redirect reader.read to the read queue so everything which reads the
    # reader directly gets the queued data in order.
    #
    # @return [Method] The original read method for the read thread to call
    def redirect_reader(reader)
      raw_read = reader.method(:read)
      # Remember a read already defined on the reader itself (e.g. a test stub)
      # so it can be put back rather than removed
      reader_read = reader.singleton_methods(false).include?(:read) ? raw_read : nil
      interface = self
      reader.define_singleton_method(:read) { |*_args| interface.read_queue_pop }
      @raw_reader = reader
      @raw_reader_read = reader_read
      return raw_read
    end

    # Undo redirect_reader so the reader reads inline again
    def restore_reader
      reader = @raw_reader
      return unless reader

      if @raw_reader_read
        reader.define_singleton_method(:read, @raw_reader_read)
      else
        reader.singleton_class.send(:remove_method, :read)
      end
    rescue NameError
      # The redirect was already removed
    ensure
      @raw_reader = nil
      @raw_reader_read = nil
    end
  end
end
