# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Integration tests for CvtModel.tsdb_lookup across db_shards.
#
# Each db_shard is a separate QuestDB so a lookup with targets on different
# db_shards runs separate queries. The results must match what ASOF JOIN returns
# when every table is on a single db_shard, so each lookup is also compared against
# the same tables written to a single db_shard.
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#        (starts questdb and questdb-shard1)
#     2. Run tests: bundle exec rspec ruby/tsdb_lookup_db_shards_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'

RSpec.describe OpenC3::CvtModel, :questdb do
  # Target name => db_shard. The SINGLE targets hold the same tables as the SHARD
  # targets but all on db_shard 0 so they are queried with a single ASOF JOIN.
  let(:db_shards) do
    { 'SHARD_A' => 0, 'SHARD_B' => 1, 'SINGLE_A' => 0, 'SINGLE_B' => 0 }
  end
  let(:single_targets) do
    { 'SHARD_A' => 'SINGLE_A', 'SHARD_B' => 'SINGLE_B' }
  end
  # [target_name, packet_name] => [[seconds after the base time, VALUE]]
  let(:tables) do
    {
      ['SHARD_A', 'PKT'] => [[0, 0], [2, 2], [4, 4]],
      # The row at 6 seconds is after the end of the lookup range
      ['SHARD_B', 'PKT'] => [[1, 1], [3, 3], [6, 6]],
      # Only a row before the start of the lookup range
      ['SHARD_B', 'EARLY'] => [[-1, 10]],
      # A row after the last SHARD_B PKT row in the lookup range
      ['SHARD_B', 'LATER'] => [[3.5, 35]],
    }
  end
  # Lists of items as [target_name, packet_name]
  let(:lookups) do
    [
      [['SHARD_A', 'PKT'], ['SHARD_B', 'PKT']],
      [['SHARD_B', 'PKT'], ['SHARD_A', 'PKT']],
      [['SHARD_A', 'PKT'], ['SHARD_B', 'EARLY']],
      [['SHARD_A', 'PKT'], ['SHARD_B', 'PKT'], ['SHARD_B', 'LATER']],
      [['SHARD_A', 'PKT'], ['SHARD_B', 'LATER'], ['SHARD_B', 'EARLY'], ['SHARD_A', 'PKT']],
      [['SHARD_B', 'LATER'], ['SHARD_A', 'PKT'], ['SHARD_B', 'PKT']],
    ]
  end
  # [start_time, end_time] as seconds after the base time
  let(:windows) do
    [[0, 5], [-2, 10], [3, 4], [5, nil], [7, nil], [3.5, nil]]
  end

  before(:each) do
    skip 'QuestDB db_shard 1 not available' unless questdb_shard1_available?

    specs = tables.flat_map do |(target_name, packet_name), rows|
      rows = rows.map { |seconds, value| { 'offset_ms' => (seconds * 1000).to_i, 'values' => { 'VALUE' => value } } }
      [target_name, single_targets[target_name]].map do |target|
        { 'target' => target, 'packet' => packet_name, 'data_type' => 'INT', 'bit_size' => 32, 'db_shard' => db_shards[target], 'rows' => rows }
      end
    end
    @test_params = write_multi_table_data({ 'tables' => specs })
    expect(@test_params['success']).to be true

    allow(OpenC3::QuestDBClient).to receive(:db_shard_for_target) { |target_name, **| db_shards.fetch(target_name) }
    allow(OpenC3::QuestDBClient).to receive(:connection).and_wrap_original do |original, db_shard: 0|
      with_db_shard_port(db_shard) { original.call(db_shard: db_shard) }
    end
    allow(OpenC3::TargetModel).to receive(:packet).and_return(@test_params['tables'][0]['packet_def'])
    OpenC3::QuestDBClient.disconnect
  end

  after(:each) do
    OpenC3::QuestDBClient.disconnect
    @test_params&.dig('tables')&.each do |table|
      cleanup_table(table['table_name'], db_shard: table['db_shard'])
    end
  end

  def iso(seconds)
    Time.at(Rational(@test_params['base_time_ns'], 1_000_000_000) + Rational(seconds.to_s)).utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
  end

  def lookup(packets, start, finish = nil)
    items = packets.map { |target_name, packet_name| [target_name, packet_name, 'VALUE', 'RAW', false] }
    OpenC3::CvtModel.tsdb_lookup(items, start_time: iso(start), end_time: finish && iso(finish))
  end

  it 'aligns the other db_shard to the first by packet time' do
    expected = [
      # SHARD_B has no row at or before 0 seconds
      [[0, nil], [nil, nil]],
      [[2, nil], [1, nil]],
      [[4, nil], [3, nil]],
    ]
    expect(lookup([['SHARD_A', 'PKT'], ['SHARD_B', 'PKT']], 0, 5)).to eq(expected)
  end

  it 'drives the rows from the db_shard of the first item' do
    expect(lookup([['SHARD_B', 'PKT'], ['SHARD_A', 'PKT']], 0, 5)).to eq([[[1, nil], [0, nil]], [[3, nil], [2, nil]]])
  end

  it 'carries forward a row before start_time' do
    expected = [[[0, nil], [10, nil]], [[2, nil], [10, nil]], [[4, nil], [10, nil]]]
    expect(lookup([['SHARD_A', 'PKT'], ['SHARD_B', 'EARLY']], 0, 5)).to eq(expected)
  end

  it 'aligns each packet on a db_shard independently' do
    # SHARD_B LATER is aligned to SHARD_A at 4 seconds, not SHARD_B PKT at 3 seconds
    packets = [['SHARD_A', 'PKT'], ['SHARD_B', 'PKT'], ['SHARD_B', 'LATER']]
    expected = [
      [[0, nil], [nil, nil], [nil, nil]],
      [[2, nil], [1, nil], [nil, nil]],
      [[4, nil], [3, nil], [35, nil]],
    ]
    expect(lookup(packets, 0, 5)).to eq(expected)
    expect(lookup(packets, 5)).to eq([[4, nil], [3, nil], [35, nil]])
  end

  it 'returns the last row at or before the driving row' do
    # SHARD_A drives at 4 seconds so SHARD_B returns its row at 3 seconds, not 6 seconds
    expect(lookup([['SHARD_A', 'PKT'], ['SHARD_B', 'PKT']], 7)).to eq([[4, nil], [3, nil]])
  end

  it 'matches a single db_shard lookup' do
    lookups.each do |packets|
      single = packets.map { |target_name, packet_name| [single_targets[target_name], packet_name] }
      windows.each do |window|
        expect(lookup(packets, *window)).to eq(lookup(single, *window)), "#{packets} #{window}"
      end
    end
  end
end
