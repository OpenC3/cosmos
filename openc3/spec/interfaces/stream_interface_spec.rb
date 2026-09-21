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

require 'spec_helper'
require 'openc3/interfaces/stream_interface'
require 'openc3/streams/stream'

module OpenC3
  describe StreamInterface do
    # Stream which returns the data it is given, one read at a time, and then
    # blocks until it is disconnected. Reads which return nil or '' mean the
    # stream is closed so a test stream can't simply return nothing.
    class QueueStream < Stream
      attr_reader :reads

      def initialize(*data)
        @queue = Queue.new
        @reads = 0
        data.each { |datum| @queue << datum }
      end

      def push(data)
        @queue << data
      end

      def connect; end

      def connected?; true; end

      def disconnect
        @queue.close
      end

      def read
        @reads += 1
        # Returns nil once the queue is closed which disconnects the interface
        @queue.pop
      end

      def write(_data); end
    end

    let(:interface) { StreamInterface.new }

    after(:each) do
      interface.disconnect
    end

    describe "read_interface" do
      it "reads ahead of read_interface and reports the queue size" do
        stream = QueueStream.new("\x01", "\x02", "\x03")
        interface.stream = stream
        interface.connect
        # The read thread drains the stream without read_interface being called
        start = Time.now
        sleep(0.001) while stream.reads < 3 and (Time.now - start) < 2
        expect(interface.read_queue_size).to eql 3

        expect(interface.read_interface()[0]).to eql "\x01"
        expect(interface.read_interface()[0]).to eql "\x02"
        expect(interface.read_interface()[0]).to eql "\x03"
        expect(interface.read_queue_size).to eql 0
      end

      it "reports the bytes waiting on the queue" do
        stream = QueueStream.new("\x01\x02", "\x03\x04\x05")
        interface.stream = stream
        interface.connect
        start = Time.now
        sleep(0.001) while interface.read_queue_size < 2 and (Time.now - start) < 2
        expect(interface.read_queue_bytes).to eql 5

        expect(interface.read_interface()[0]).to eql "\x01\x02"
        expect(interface.read_queue_bytes).to eql 3
        expect(interface.read_interface()[0]).to eql "\x03\x04\x05"
        expect(interface.read_queue_bytes).to eql 0
      end

      it "blocks until the read thread queues data" do
        stream = QueueStream.new
        interface.stream = stream
        interface.connect
        thread = Thread.new { Thread.current[:data] = interface.read_interface()[0] }
        sleep(0.01)
        expect(thread.alive?).to be true
        stream.push("\x01\x02")
        thread.join(2)
        expect(thread[:data]).to eql "\x01\x02"
      end

      it "counts the bytes read as they are dequeued" do
        stream = QueueStream.new("\x01\x02\x03")
        interface.stream = stream
        interface.connect
        expect(interface.read_interface()[0]).to eql "\x01\x02\x03"
        expect(interface.bytes_read).to eql 3
      end

      it "returns nil when the stream closes" do
        stream = QueueStream.new("\x01", '')
        interface.stream = stream
        interface.connect
        expect(interface.read_interface()[0]).to eql "\x01"
        expect(interface.read_interface()).to be_nil
        # Still nil rather than blocking forever now the read thread is done
        expect(interface.read_interface()).to be_nil
      end

      it "re-raises exceptions from the read thread" do
        error = RuntimeError.new("read failed")
        stream = QueueStream.new
        allow(stream).to receive(:read).and_raise(error)
        interface.stream = stream
        interface.connect
        expect { interface.read_interface() }.to raise_error(error)
      end

      it "returns nil on a read timeout" do
        stream = QueueStream.new
        allow(stream).to receive(:read).and_raise(Timeout::Error)
        interface.stream = stream
        interface.connect
        expect(interface.read_interface()).to be_nil
      end

      it "does not start a read thread when reading isn't allowed" do
        interface.read_allowed = false
        stream = QueueStream.new("\x01")
        interface.stream = stream
        interface.connect
        sleep(0.01)
        expect(stream.reads).to eql 0
        expect(interface.read_queue_size).to eql 0
      end
    end

    describe "set_option" do
      it "limits how many bytes are buffered" do
        # Each queued read is also charged the per entry overhead so budget for
        # exactly two of the two byte reads below
        max_size = 2 * (2 + ReadQueue::READ_QUEUE_ENTRY_OVERHEAD)
        interface.set_option('READ_QUEUE_MAX_SIZE', [max_size.to_s])
        expect(interface.read_queue_max_size).to eql max_size
        stream = QueueStream.new("\x01\x02", "\x03\x04", "\x05\x06")
        interface.stream = stream
        interface.connect
        sleep(0.05)
        # The read thread blocks on the third read rather than going over budget
        expect(interface.read_queue_bytes).to eql 4
        expect(interface.read_queue_size).to eql 2

        # Dequeuing makes room so the read thread queues the read it was holding
        expect(interface.read_interface()[0]).to eql "\x01\x02"
        start = Time.now
        sleep(0.001) while interface.read_queue_bytes < 4 and (Time.now - start) < 2
        expect(interface.read_queue_bytes).to eql 4
      end

      it "queues a read larger than the entire budget on its own" do
        interface.set_option('READ_QUEUE_MAX_SIZE', ['2'])
        stream = QueueStream.new("\x01\x02\x03\x04\x05")
        interface.stream = stream
        interface.connect
        # Otherwise the read would never fit and the interface would stall
        expect(interface.read_interface()[0]).to eql "\x01\x02\x03\x04\x05"
      end

      it "raises if the max size isn't positive" do
        expect { interface.set_option('READ_QUEUE_MAX_SIZE', ['0']) }.to \
          raise_error(/READ_QUEUE_MAX_SIZE must be a positive integer/)
      end
    end

    describe "disconnect" do
      it "stops the read thread and clears the queue" do
        stream = QueueStream.new("\x01", "\x02")
        interface.stream = stream
        interface.connect
        sleep(0.01)
        expect(interface.read_queue_size).to be > 0
        interface.disconnect
        expect(interface.read_queue_size).to eql 0
        expect(interface.read_queue_bytes).to eql 0
        expect(interface.instance_variable_get(:@raw_read_thread)).to be_nil
      end
    end

    describe "stream=" do
      it "stops the read thread reading the old stream" do
        old_stream = QueueStream.new("\x01")
        interface.stream = old_stream
        interface.connect
        sleep(0.01)
        expect(interface.read_queue_size).to eql 1
        interface.stream = QueueStream.new("\x02")
        expect(interface.read_queue_size).to eql 0
        expect(interface.read_interface()[0]).to eql "\x02"
      end
    end
  end
end
