# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/file_interface'
require 'fileutils'
require 'tempfile'

module OpenC3
  describe FileInterface do
    before(:each) do
      @interface = nil
      @temp_dir = Dir.mktmpdir
      @telemetry_dir = File.join(@temp_dir, 'telemetry')
      @command_dir = File.join(@temp_dir, 'command')
      @archive_dir = File.join(@temp_dir, 'archive')
      FileUtils.mkdir_p(@telemetry_dir)
      FileUtils.mkdir_p(@command_dir)
      FileUtils.mkdir_p(@archive_dir)
    end

    after(:each) do
      @interface.disconnect if @interface
      FileUtils.remove_entry_secure(@temp_dir) if File.exist?(@temp_dir)
    end

    describe "initialize" do
      it "initializes the instance variables" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        expect(@interface.instance_variable_get(:@command_write_folder)).to eq @command_dir
        expect(@interface.instance_variable_get(:@telemetry_read_folder)).to eq @telemetry_dir
        expect(@interface.instance_variable_get(:@telemetry_archive_folder)).to eq @archive_dir
        expect(@interface.instance_variable_get(:@file_read_size)).to eq 65536
        expect(@interface.instance_variable_get(:@stored)).to be true
        expect(@interface.instance_variable_get(:@extension)).to eq ".bin"
        expect(@interface.instance_variable_get(:@label)).to eq "command"
        expect(@interface.instance_variable_get(:@polling)).to be false
        expect(@interface.instance_variable_get(:@recursive)).to be false
      end

      it "handles nil folders appropriately" do
        @interface = FileInterface.new(nil, nil, nil)
        expect(@interface.instance_variable_get(:@command_write_folder)).to be_nil
        expect(@interface.instance_variable_get(:@telemetry_read_folder)).to be_nil
        expect(@interface.instance_variable_get(:@telemetry_archive_folder)).to be_nil
        expect(@interface.read_allowed?).to be false
        expect(@interface.write_allowed?).to be false
        expect(@interface.write_raw_allowed?).to be false
      end

      it "initializes with a protocol" do
        protocol_type = "Preidentified"
        protocol_args = [nil, 100]
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir, 65536, true, protocol_type, *protocol_args)
        expect(@interface.read_protocols.length).to eq 1
        expect(@interface.write_protocols.length).to eq 1
      end
    end

    describe "connect" do
      it "connects and sets up the listener" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        expect(@interface.connected?).to be false
        @interface.connect
        expect(@interface.connected?).to be true
        expect(@interface.instance_variable_get(:@listener)).to_not be_nil
      end

      it "doesn't setup the listener if no telemetry folder" do
        @interface = FileInterface.new(@command_dir, nil, nil)
        @interface.connect
        expect(@interface.connected?).to be true
        expect(@interface.instance_variable_get(:@listener)).to be_nil
      end
    end

    describe "disconnect" do
      it "closes the file if open" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        mock_file = double("file")
        expect(mock_file).to receive(:closed?).and_return(false)
        expect(mock_file).to receive(:close)
        @interface.instance_variable_set(:@file, mock_file)
        @interface.disconnect
        expect(@interface.instance_variable_get(:@file)).to be_nil
      end
    end

    describe "read_interface" do
      it "returns nil if no telemetry files available" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect
        allow(@interface).to receive(:get_next_telemetry_file).and_return(nil)
        # Empty the queue
        @interface.instance_variable_get(:@queue).clear
        # Push nil to ensure pop returns immediately
        @interface.instance_variable_get(:@queue).push(nil)
        data, extra = @interface.read_interface
        expect(data).to be_nil
        expect(extra).to be_nil
      end

      it "reads data from a telemetry file" do
        filename = File.join(@telemetry_dir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect
        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
        # Push a dummy value so when we call read_interface again it doesn't block
        @interface.instance_variable_get(:@queue).push(nil)
        data, extra = @interface.read_interface
        # Verify the file was archived
        expect(File.exist?(File.join(@archive_dir, 'test.bin'))).to be true
        expect(File.exist?(filename)).to be false
      end

      it "reads data from a gzipped telemetry file" do
        filename = File.join(@telemetry_dir, 'test.bin.gz')
        Zlib::GzipWriter.open(filename) do |gz|
          gz.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect
        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
      end

      it "deletes the file if archive folder is DELETE" do
        filename = File.join(@telemetry_dir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, "DELETE")
        @interface.connect
        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
        # Push a dummy value so when we call read_interface again it doesn't block
        @interface.instance_variable_get(:@queue).push(nil)
        data, extra = @interface.read_interface
        expect(File.exist?(filename)).to be false
      end

      it "respects file_read_size" do
        filename = File.join(@telemetry_dir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04\x05\x06\x07\x08")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir, 4)
        @interface.connect
        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
        data, extra = @interface.read_interface
        expect(data).to eql "\x05\x06\x07\x08"
        # The file should now be empty so we should get nil
        allow(@interface).to receive(:get_next_telemetry_file).and_return(nil)
        # Empty the queue
        @interface.instance_variable_get(:@queue).clear
        # Push nil to ensure pop returns immediately
        @interface.instance_variable_get(:@queue).push(nil)
        data, extra = @interface.read_interface
        expect(data).to be_nil
        expect(extra).to be_nil
      end

      it "respects throttle option" do
        filename1 = File.join(@telemetry_dir, 'test1.bin')
        File.open(filename1, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        filename2 = File.join(@telemetry_dir, 'test2.bin')
        File.open(filename2, 'wb') do |file|
          file.write("\x05\x06\x07\x08")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('THROTTLE', ['0.2'])
        @interface.connect
        start = Time.now.to_f
        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
        data, extra = @interface.read_interface
        expect(data).to eql "\x05\x06\x07\x08"
        expect(Time.now.to_f - start).to be > 0.2
        expect(Time.now.to_f - start).to be < 1.0
      end

      it "responds to file notifications via the queue" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect

        # Setup to create a file after we're waiting on the queue
        Thread.new do
          sleep 0.1 # Give the main thread time to get to the queue.pop
          filename = File.join(@telemetry_dir, 'test.bin')
          File.open(filename, 'wb') do |file|
            file.write("\x01\x02\x03\x04")
          end
          @interface.instance_variable_get(:@queue).push([filename])
        end

        data, extra = @interface.read_interface
        expect(data).to eql "\x01\x02\x03\x04"
      end
    end

    describe "write_interface" do
      it "writes data to a command file" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect
        data = "\x01\x02\x03\x04"
        result, extra = @interface.write_interface(data)
        expect(result).to eql data
        expect(extra).to be_nil
        # Verify a file was created
        files = Dir.glob(File.join(@command_dir, '*'))
        expect(files.length).to eql 1
        file_data = File.read(files[0])
        expect(file_data).to eql data
      end
    end

    describe "set_option" do
      it "handles LABEL option" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('LABEL', ['new_label'])
        expect(@interface.instance_variable_get(:@label)).to eql 'new_label'
      end

      it "handles EXTENSION option" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('EXTENSION', ['.txt'])
        expect(@interface.instance_variable_get(:@extension)).to eql '.txt'
      end

      it "handles POLLING option" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('POLLING', ['TRUE'])
        expect(@interface.instance_variable_get(:@polling)).to be true
      end

      it "handles RECURSIVE option" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('RECURSIVE', ['TRUE'])
        expect(@interface.instance_variable_get(:@recursive)).to be true
      end

      it "handles THROTTLE option" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('THROTTLE', ['100'])
        expect(@interface.instance_variable_get(:@throttle)).to eq 100
        expect(@interface.instance_variable_get(:@sleeper)).to_not be_nil
      end
    end

    describe "finish_file" do
      it "closes and archives the file" do
        filename = File.join(@telemetry_dir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.connect
        file = File.open(filename, 'rb')
        @interface.instance_variable_set(:@file, file)
        @interface.finish_file
        expect(@interface.instance_variable_get(:@file)).to be_nil
        expect(File.exist?(filename)).to be false
        expect(File.exist?(File.join(@archive_dir, 'test.bin'))).to be true
      end

      it "deletes the file if archive folder is DELETE" do
        filename = File.join(@telemetry_dir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, "DELETE")
        @interface.connect
        file = File.open(filename, 'rb')
        @interface.instance_variable_set(:@file, file)
        @interface.finish_file
        expect(@interface.instance_variable_get(:@file)).to be_nil
        expect(File.exist?(filename)).to be false
      end
    end

    describe "get_next_telemetry_file" do
      it "returns the first file in the telemetry directory" do
        filename1 = File.join(@telemetry_dir, 'test1.bin')
        File.open(filename1, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        sleep 0.1 # Ensure file timestamps are different
        filename2 = File.join(@telemetry_dir, 'test2.bin')
        File.open(filename2, 'wb') do |file|
          file.write("\x05\x06\x07\x08")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        result = @interface.get_next_telemetry_file
        expect(result).to eql filename1
      end

      it "returns nil if no files exist" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        result = @interface.get_next_telemetry_file
        expect(result).to be_nil
      end

      it "finds files recursively if recursive option set" do
        subdir = File.join(@telemetry_dir, 'subdir')
        FileUtils.mkdir_p(subdir)
        filename = File.join(subdir, 'test.bin')
        File.open(filename, 'wb') do |file|
          file.write("\x01\x02\x03\x04")
        end
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        @interface.set_option('RECURSIVE', ['TRUE'])
        result = @interface.get_next_telemetry_file
        expect(result).to eql filename
      end
    end

    describe "create_unique_filename" do
      it "creates a unique filename" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        filename = @interface.create_unique_filename
        expect(filename).to include(@command_dir)
        expect(filename).to include('command')
        expect(filename).to include('.bin')
        expect(File.exist?(filename)).to be false
      end

      it "handles existing files by adding a counter" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir)
        # Mock the File class to make it think the file exists
        # No idea why this is called three times ...
        expect(File).to receive(:exist?).and_return(true, false, false)
        filename = @interface.create_unique_filename
        expect(filename).to include('command_1')
      end
    end

    describe "convert_data_to_packet" do
      it "sets the stored flag if configured" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir, 65536, true)
        packet = Packet.new('TGT', 'PKT')
        allow(@interface).to receive(:super).and_return(packet)
        result = @interface.convert_data_to_packet("\x01\x02\x03\x04")
        expect(result.stored).to be true
      end

      it "doesn't set the stored flag if not configured" do
        @interface = FileInterface.new(@command_dir, @telemetry_dir, @archive_dir, 65536, false)
        packet = Packet.new('TGT', 'PKT')
        allow(@interface).to receive(:super).and_return(packet)
        result = @interface.convert_data_to_packet("\x01\x02\x03\x04")
        expect(result.stored).to be false
      end
    end
  end
end