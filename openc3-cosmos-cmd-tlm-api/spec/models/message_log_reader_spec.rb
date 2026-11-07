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

require "rails_helper"
require "tempfile"

RSpec.describe MessageLogReader, type: :model do
  let(:bucket_file) { double("bucket_file") }
  let(:reader) { MessageLogReader.new(bucket_file) }

  def write_log(lines)
    file = Tempfile.new(["messages", ".txt"])
    file.write(lines.join)
    file.close
    file
  end

  after(:each) do
    reader.close
    @file&.unlink
  end

  it "exposes the bucket_file" do
    expect(reader.bucket_file).to eql(bucket_file)
  end

  it "returns nil before a file is opened" do
    expect(reader.next_entry_time).to be_nil
    expect(reader.read).to be_nil
  end

  it "reads entries one at a time in file order" do
    @file = write_log([
      JSON.generate({ "time" => 100, "message" => "one" }) + "\n",
      JSON.generate({ "time" => 200, "message" => "two" }) + "\n",
      JSON.generate({ "time" => 300, "message" => "three" }) + "\n",
    ])
    reader.open(@file.path)
    expect(reader.next_entry_time).to eql(100)
    expect(reader.read["message"]).to eql("one")
    expect(reader.next_entry_time).to eql(200)
    expect(reader.read["message"]).to eql("two")
    expect(reader.read["message"]).to eql("three")
    expect(reader.next_entry_time).to be_nil
    expect(reader.read).to be_nil
  end

  it "handles a final line without a trailing newline" do
    @file = write_log([JSON.generate({ "time" => 100, "message" => "only" })])
    reader.open(@file.path)
    expect(reader.read["message"]).to eql("only")
    expect(reader.read).to be_nil
  end

  it "stops at the first non-JSON line" do
    @file = write_log([
      JSON.generate({ "time" => 100, "message" => "one" }) + "\n",
      "\n",
      JSON.generate({ "time" => 200, "message" => "two" }) + "\n",
    ])
    reader.open(@file.path)
    expect(reader.read["message"]).to eql("one")
    expect(reader.read).to be_nil
  end

  it "handles an empty file" do
    @file = write_log([])
    reader.open(@file.path)
    expect(reader.next_entry_time).to be_nil
  end

  it "does not read the whole file up front" do
    @file = write_log([JSON.generate({ "time" => 100, "message" => "one" }) + "\n"])
    expect(File).not_to receive(:read)
    reader.open(@file.path)
    expect(reader.read["message"]).to eql("one")
  end

  it "closes the file handle once the file is exhausted" do
    @file = write_log([JSON.generate({ "time" => 100, "message" => "one" }) + "\n"])
    handle = File.open(@file.path, 'r')
    allow(File).to receive(:open).with(@file.path, 'r').and_return(handle)
    reader.open(@file.path)
    expect(handle.closed?).to be false
    reader.read
    expect(handle.closed?).to be true
  end

  it "closes the file handle on close and on reopen" do
    @file = write_log([
      JSON.generate({ "time" => 100, "message" => "one" }) + "\n",
      JSON.generate({ "time" => 200, "message" => "two" }) + "\n",
    ])
    first = File.open(@file.path, 'r')
    second = File.open(@file.path, 'r')
    allow(File).to receive(:open).with(@file.path, 'r').and_return(first, second)
    reader.open(@file.path)
    reader.open(@file.path)
    expect(first.closed?).to be true
    expect(reader.read["message"]).to eql("one")
    reader.close
    expect(second.closed?).to be true
    expect(reader.next_entry_time).to be_nil
  end
end
