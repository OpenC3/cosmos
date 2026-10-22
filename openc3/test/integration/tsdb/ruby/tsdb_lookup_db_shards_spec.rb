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
# db_shards runs one query per db_shard. A range lookup must align those rows by
# packet time (the way ASOF JOIN aligns tables within a db_shard) rather than by
# row number.
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#        (starts questdb and questdb-shard1)
#     2. Run tests: bundle exec rspec ruby/tsdb_lookup_db_shards_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'

RSpec.describe OpenC3::CvtModel, :questdb do
  # Target name => db_shard
  let(:db_shards) { { 'SHARD_A' => 0, 'SHARD_B' => 1 } }

  before(:each) do
    skip 'QuestDB db_shard 1 not available' unless questdb_shard1_available?

    rows = lambda do |seconds_list|
      seconds_list.map { |seconds| { 'offset_ms' => seconds * 1000, 'values' => { 'VALUE' => seconds } } }
    end
    tables = [
      { 'target' => 'SHARD_A', 'packet' => 'PKT', 'data_type' => 'INT', 'bit_size' => 32, 'db_shard' => 0, 'rows' => rows.call([0, 2, 4]) },
      # The row at 6 seconds is after the end of the lookup range
      { 'target' => 'SHARD_B', 'packet' => 'PKT', 'data_type' => 'INT', 'bit_size' => 32, 'db_shard' => 1, 'rows' => rows.call([1, 3, 6]) },
    ]
    @test_params = write_multi_table_data({ 'tables' => tables })
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
    Time.at((@test_params['base_time_ns'] / 1_000_000_000) + seconds).utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
  end

  def items(*target_names)
    target_names.map { |target_name| [target_name, 'PKT', 'VALUE', 'RAW', false] }
  end

  it 'aligns the other db_shard to the first by packet time' do
    result = OpenC3::CvtModel.tsdb_lookup(items('SHARD_A', 'SHARD_B'), start_time: iso(0), end_time: iso(5))
    expected = [
      # SHARD_B has no row at or before 0 seconds
      [[0, nil], [nil, nil]],
      [[2, nil], [1, nil]],
      [[4, nil], [3, nil]],
    ]
    expect(result).to eq(expected)
  end

  it 'drives the rows from the db_shard of the first item' do
    result = OpenC3::CvtModel.tsdb_lookup(items('SHARD_B', 'SHARD_A'), start_time: iso(0), end_time: iso(5))
    expect(result).to eq([[[1, nil], [0, nil]], [[3, nil], [2, nil]]])
  end

  it 'returns the last row before start_time from each db_shard' do
    result = OpenC3::CvtModel.tsdb_lookup(items('SHARD_A', 'SHARD_B'), start_time: iso(5))
    expect(result).to eq([[4, nil], [3, nil]])
  end
end
