# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Integration tests for QuestDBClient db_shard routing against two real QuestDBs.
#
# OPENC3_TSDB_HOSTNAME is tsdb-SHARDNUM like a db_sharded deployment so the client
# resolves each db_shard to its own host with hostname_for_db_shard. Locally both
# QuestDBs run on 127.0.0.1 so connections to tsdb-<N> are sent to the query port
# of db_shard N (questdb and questdb-shard1 in docker-compose.test.yml). Everything
# else (queries, reconnects) runs against the real QuestDBs.
#
# Run with:
#     1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
#        (starts questdb and questdb-shard1)
#     2. Run tests: bundle exec rspec ruby/questdb_db_shards_spec.rb
#     3. Stop QuestDB: docker compose -f docker-compose.test.yml down

require_relative 'spec_helper'

RSpec.describe OpenC3::QuestDBClient, :questdb do
  let(:query_ports) do
    { 'tsdb-0' => ENV.fetch('OPENC3_TSDB_QUERY_PORT'), 'tsdb-1' => ENV.fetch('OPENC3_TSDB_SHARD1_QUERY_PORT') }
  end

  before(:each) do
    skip 'QuestDB db_shard 1 not available' unless questdb_shard1_available?

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OPENC3_TSDB_HOSTNAME').and_return('tsdb-SHARDNUM')
    # Send a connection to tsdb-<N> to the QuestDB of db_shard N
    allow(PG::Connection).to receive(:new).and_wrap_original do |original, **kwargs|
      port = query_ports[kwargs[:host]]
      raise PG::ConnectionBad, "unknown host #{kwargs[:host]}" unless port

      original.call(**kwargs, host: '127.0.0.1', port: port)
    end
    OpenC3::QuestDBClient.disconnect
  end

  after(:each) do
    OpenC3::QuestDBClient.disconnect
    @test_params&.dig('tables')&.each do |table|
      cleanup_table(table['table_name'], db_shard: table['db_shard'])
    end
  end

  # The same DBSHARD PKT table on both db_shards. db_shard 0 has an INT VALUE of
  # 100 and 200 and db_shard 1 has a FLOAT VALUE of 1, 2 and 3.
  def write_both_db_shards
    rows = ->(values) { values.each_with_index.map { |value, index| { 'offset_ms' => index * 1000, 'values' => { 'VALUE' => value } } } }
    tables = [
      { 'target' => 'DBSHARD', 'packet' => 'PKT', 'data_type' => 'INT', 'bit_size' => 32, 'db_shard' => 0, 'rows' => rows.call([100, 200]) },
      { 'target' => 'DBSHARD', 'packet' => 'PKT', 'data_type' => 'FLOAT', 'bit_size' => 64, 'db_shard' => 1, 'rows' => rows.call([1.0, 2.0, 3.0]) },
    ]
    @test_params = write_multi_table_data({ 'tables' => tables })
    expect(@test_params['success']).to be true
    @table_name = @test_params['tables'][0]['table_name']
  end

  def count(db_shard)
    OpenC3::QuestDBClient.query_with_retry("SELECT count() as count FROM \"#{@table_name}\"", db_shard: db_shard).getvalue(0, 0)
  end

  it "looks up a target on the QuestDB of its db_shard" do
    write_both_db_shards
    { 1 => [1.0, 2.0, 3.0], 0 => [100, 200] }.each do |db_shard, expected|
      allow(OpenC3::QuestDBClient).to receive(:db_shard_for_target).and_return(db_shard)
      allow(OpenC3::TargetModel).to receive(:packet).and_return(@test_params['tables'][db_shard]['packet_def'])
      items = [['DBSHARD', 'PKT', 'VALUE', 'RAW', false]]
      result = OpenC3::CvtModel.tsdb_lookup(items, start_time: @test_params['start_time'], end_time: @test_params['end_time'])
      expect(result.map { |row| row[0][0] }).to eql(expected), "db_shard #{db_shard}"
    end
  end

  it "keeps a connection per db_shard" do
    write_both_db_shards
    conn0 = OpenC3::QuestDBClient.connection(db_shard: 0)
    conn1 = OpenC3::QuestDBClient.connection(db_shard: 1)
    expect(conn0).not_to be conn1
    expect(OpenC3::QuestDBClient.connection(db_shard: 1)).to be conn1
    expect(count(0)).to eql 2
    expect(count(1)).to eql 3

    OpenC3::QuestDBClient.disconnect(db_shard: 1)
    expect(conn1.finished?).to be true
    expect(conn0.finished?).to be false
    # db_shard 0 keeps its connection and db_shard 1 reconnects to its own QuestDB
    expect(OpenC3::QuestDBClient.connection(db_shard: 0)).to be conn0
    expect(count(0)).to eql 2
    expect(count(1)).to eql 3
    expect(OpenC3::QuestDBClient.connection(db_shard: 1)).not_to be conn1
  end

  it "reconnects the db_shard whose connection was lost" do
    write_both_db_shards
    conn0 = OpenC3::QuestDBClient.connection(db_shard: 0)
    conn1 = OpenC3::QuestDBClient.connection(db_shard: 1)
    # Kill the db_shard 1 connection out from under the client
    conn1.socket_io.close
    allow(OpenC3::QuestDBClient).to receive(:sleep)
    expect(count(1)).to eql 3
    expect(OpenC3::QuestDBClient.connection(db_shard: 1)).not_to be conn1
    expect(OpenC3::QuestDBClient.connection(db_shard: 0)).to be conn0
    expect(count(0)).to eql 2
  end

  it "checks for table data on the QuestDB of the db_shard" do
    table = { 'target' => 'DBSHARD', 'packet' => 'PKT', 'data_type' => 'INT', 'bit_size' => 32, 'db_shard' => 1,
              'rows' => [{ 'offset_ms' => 0, 'values' => { 'VALUE' => 1 } }] }
    @test_params = write_multi_table_data({ 'tables' => [table] })
    expect(@test_params['success']).to be true
    table_name = @test_params['tables'][0]['table_name']
    start_time = @test_params['base_time_ns']
    end_time = start_time + 10_000_000_000
    expect(OpenC3::QuestDBClient.table_has_data?(table_name, start_time, end_time, db_shard: 1)).to be true
    # The table doesn't exist on db_shard 0
    expect(OpenC3::QuestDBClient.table_has_data?(table_name, start_time, end_time, db_shard: 0)).to be false
    # No data in the range on db_shard 1
    expect(OpenC3::QuestDBClient.table_has_data?(table_name, end_time, end_time + 1, db_shard: 1)).to be false
  end

  it "gets the table columns from the QuestDB of the db_shard" do
    write_both_db_shards
    expect(OpenC3::QuestDBClient.table_columns(@table_name, db_shard: 0)['VALUE']).to eql 'LONG'
    expect(OpenC3::QuestDBClient.table_columns(@table_name, db_shard: 1)['VALUE']).to eql 'DOUBLE'
  end

  it "paginates a query on the QuestDB of the db_shard" do
    write_both_db_shards
    values = Hash.new { |hash, key| hash[key] = [] }
    [0, 1].each do |db_shard|
      OpenC3::QuestDBClient.paginate_query("SELECT VALUE FROM \"#{@table_name}\"", 2, label: 'test', db_shard: db_shard) do |page|
        values[db_shard].concat(page.column_values(0))
      end
    end
    expect(values).to eql({ 0 => [100, 200], 1 => [1.0, 2.0, 3.0] })
  end

  it "checks the connection of each db_shard" do
    expect(OpenC3::QuestDBClient.check_connection(db_shard: 0)).to be true
    expect(OpenC3::QuestDBClient.check_connection(db_shard: 1)).to be true
    # There is no QuestDB for db_shard 2
    expect { OpenC3::QuestDBClient.check_connection(db_shard: 2) }.to raise_error(PG::ConnectionBad)
  end
end
