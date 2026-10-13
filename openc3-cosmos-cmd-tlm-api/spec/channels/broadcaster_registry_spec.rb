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

RSpec.describe ApplicationCable::BroadcasterRegistry do
  let(:registry) { described_class }
  let(:broadcaster) { double("broadcaster", kill: nil) }

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  before(:each) do
    registry.clear
    allow(OpenC3::Logger).to receive(:warn)
    allow(OpenC3::Logger).to receive(:error)
  end
  after(:each) { registry.clear }

  it "registers, gets and unregisters" do
    registry.register('key', broadcaster)
    expect(registry.get('key')).to equal(broadcaster)
    expect(broadcaster).to receive(:kill)
    expect(registry.unregister('key')).to be true
    expect(registry.get('key')).to be_nil
    expect(registry.unregister('key')).to be false
  end

  it "touch returns false for unknown keys" do
    expect(registry.touch('missing', heartbeat: true)).to be false
  end

  it "keeps heartbeating entries alive while they heartbeat" do
    registry.register('key', broadcaster)
    registry.touch('key', heartbeat: true)
    expect(registry.sweep(now + registry.ttl - 5)).to be_empty
    expect(registry.registered?('key')).to be true
  end

  it "reaps only heartbeating entries past the ttl" do
    legacy = double("legacy", kill: nil)
    registry.register('key', broadcaster)
    registry.register('legacy', legacy)
    registry.touch('key', heartbeat: true)
    expect(broadcaster).to receive(:kill)
    expect(legacy).not_to receive(:kill)
    expect(registry.sweep(now + registry.ttl + 1)).to eql ['key']
    expect(registry.registered?('legacy')).to be true
  end

  it "honors OPENC3_CABLE_SUBSCRIPTION_TTL" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('OPENC3_CABLE_SUBSCRIPTION_TTL', anything).and_return('10')
    registry.register('key', broadcaster)
    registry.touch('key', heartbeat: true)
    expect(registry.sweep(now + 11)).to eql ['key']
  end

  it "survives a broadcaster whose kill raises" do
    allow(broadcaster).to receive(:kill).and_raise("boom")
    registry.register('key', broadcaster)
    registry.touch('key', heartbeat: true)
    expect(registry.sweep(now + registry.ttl + 1)).to eql ['key']
  end
end
