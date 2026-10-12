# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# End-to-end tests for historical get_tlm_values with LATEST items.
#
# LATEST must return the value from whichever packet containing the item was
# received most recently at the requested time, not the packet received most
# recently now, and not just the first packet in the QuestDB ASOF JOIN.
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#     2. Run tests: bundle exec rspec ruby/tlm_api_latest_tsdb_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'
require 'openc3/api/tlm_api'
require 'openc3/utilities/authorization'

RSpec.describe 'get_tlm_values with historical LATEST', :questdb do
  class LatestApi
    include OpenC3::Api
    include OpenC3::Authorization
  end

  # Timeline in ms from the base time (VALUE written to each packet):
  #   PKT_A:   0 => 1, 2000 => 3
  #   PKT_B:   1000 => 2, 3000 => 4
  #   REGULAR: 500 => 10, 1500 => 20, 2500 => 30, 3500 => 40
  before(:all) do
    @test_params = write_multi_table_data({
      'tables' => [
        { 'target' => 'RUBY_LT', 'packet' => 'PKT_A', 'data_type' => 'INT', 'bit_size' => 32,
          'rows' => [{ 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } }, { 'offset_ms' => 2000, 'values' => { 'VALUE' => 3 } }] },
        { 'target' => 'RUBY_LT', 'packet' => 'PKT_B', 'data_type' => 'INT', 'bit_size' => 32,
          'rows' => [{ 'offset_ms' => 1000, 'values' => { 'VALUE' => 2 } }, { 'offset_ms' => 3000, 'values' => { 'VALUE' => 4 } }] },
        { 'target' => 'RUBY_LT', 'packet' => 'REGULAR', 'data_type' => 'INT', 'bit_size' => 32,
          'rows' => [500, 1500, 2500, 3500].each_with_index.map { |offset, i| { 'offset_ms' => offset, 'values' => { 'VALUE' => (i + 1) * 10 } } } },
      ]
    })
  end

  before(:each) do
    OpenC3::QuestDBClient.disconnect
    expect(@test_params['success']).to be true
    packet_defs = @test_params['tables'].to_h { |table| [table['packet_name'], table['packet_def']] }
    allow(OpenC3::TargetModel).to receive(:packet) { |_target_name, packet_name, **| packet_defs.fetch(packet_name) }
    allow(OpenC3::TargetModel).to receive(:get_item_to_packet_map).and_return({ 'VALUE' => ['PKT_A', 'PKT_B'] })
    @api = LatestApi.new
    allow(@api).to receive(:authorize)
  end

  after(:each) do
    OpenC3::QuestDBClient.disconnect
  end

  def time_at(offset_ms)
    ns = @test_params['base_time_ns'] + (offset_ms * 1_000_000)
    Time.at(ns / 1_000_000_000, ns % 1_000_000_000, :nsec).utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
  end

  it 'returns the packet received most recently at a point in time' do
    expect(@api.get_tlm_values(['RUBY_LT__LATEST__VALUE__RAW'], start_time: time_at(2500))).to eq([[3, nil]])
  end

  it 'returns a packet received after the last row of the first candidate' do
    # PKT_A was last received at 2000 but PKT_B at 3000 so PKT_B is the latest at 3500
    expect(@api.get_tlm_values(['RUBY_LT__LATEST__VALUE__RAW'], start_time: time_at(3500))).to eq([[4, nil]])
  end

  it 'returns LATEST alongside a regular item at a point in time' do
    vals = @api.get_tlm_values(['RUBY_LT__LATEST__VALUE__RAW', 'RUBY_LT__REGULAR__VALUE__RAW'], start_time: time_at(3600))
    expect(vals).to eq([[4, nil], [40, nil]])
  end

  it 'returns the latest packet at each row of a range driven by a regular item' do
    vals = @api.get_tlm_values(['RUBY_LT__LATEST__VALUE__RAW', 'RUBY_LT__REGULAR__VALUE__RAW'],
                               start_time: time_at(0), end_time: time_at(4000))
    expect(vals).to eq([
      [[1, nil], [10, nil]],
      [[2, nil], [20, nil]],
      [[3, nil], [30, nil]],
      [[4, nil], [40, nil]],
    ])
  end
end
