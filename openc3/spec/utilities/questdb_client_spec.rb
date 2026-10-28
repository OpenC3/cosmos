# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "spec_helper"
require "openc3/utilities/questdb_client"

module OpenC3
  describe QuestDBClient, no_ext: true do
    describe "tsdb_lookup" do
      it "returns a row of nils when every item is a placeholder" do
        # get_tlm_available returns nil for items which don't exist, which arrive
        # here as [nil, nil, nil, nil, nil]. There's no table to query so the values
        # come back nil rather than building a query with no FROM clause.
        items = Array.new(3) { Array.new(5) }
        expect(QuestDBClient.tsdb_lookup(items, start_time: "2026-09-13T00:00:00Z", end_time: "2026-09-13T01:00:00Z")).to eq([[nil, nil], [nil, nil], [nil, nil]])
      end

      it "returns a row of nils for a placeholder without an end_time" do
        expect(QuestDBClient.tsdb_lookup([Array.new(5)], start_time: "2026-09-13T00:00:00Z")).to eq([[nil, nil]])
      end

      context "with items across db_shards" do
        let(:items) do
          [
            ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", nil],
            ["INST2", "HEALTH_STATUS", "TEMP1", "CONVERTED", nil],
            ["INST", "HEALTH_STATUS", "TEMP2", "CONVERTED", nil],
          ]
        end

        def lookup(results, end_time: nil, seeds: nil)
          # INST is on db_shard 0 and INST2 is on db_shard 1
          allow(QuestDBClient).to receive(:db_shard_for_target) { |target_name, **| target_name == "INST2" ? 1 : 0 }
          allow(QuestDBClient).to receive(:tsdb_lookup_single_db_shard) do |_items, db_shard:, flatten:, end_time: nil, **|
            expect(flatten).to be false
            # A range lookup seeds the other db_shards with a point in time (no end_time) query
            next seeds.fetch(db_shard, {}) if seeds and end_time.nil?

            results[db_shard]
          end
          QuestDBClient.tsdb_lookup(items, start_time: "2026-09-13T00:00:00Z", end_time: end_time)
        end

        it "queries each db_shard and merges a single row" do
          result = lookup({ 0 => [[[1.0, nil], [3.0, "RED"]]], 1 => [[[2.0, nil]]] })
          expect(result).to eq([[1.0, nil], [2.0, nil], [3.0, "RED"]])
          expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).with([items[0], items[2]], hash_including(db_shard: 0))
          expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).with([items[1]], hash_including(db_shard: 1))
        end

        it "fills a db_shard with no results with nils" do
          expect(lookup({ 0 => [[[1.0, nil], [3.0, nil]]], 1 => {} })).to eq([[1.0, nil], [nil, nil], [3.0, nil]])
        end

        context "with an end_time" do
          # Range rows end with the packet time added to each db_shard query
          def range_lookup(results, seeds: {})
            lookup(results, end_time: "2026-09-13T01:00:00Z", seeds: seeds)
          end

          it "adds the packet time of the first packet to each db_shard query" do
            range_lookup({ 0 => [[[1.0, nil], [3.0, nil], [10.0, nil]]], 1 => [[[2.0, nil], [10.0, nil]]] })
            time = ["INST", "HEALTH_STATUS", "PACKET_TIMESECONDS", "RAW", nil]
            time2 = ["INST2", "HEALTH_STATUS", "PACKET_TIMESECONDS", "RAW", nil]
            expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).with([items[0], items[2], time], hash_including(db_shard: 0, end_time: "2026-09-13T01:00:00Z"))
            expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).with([items[1], time2], hash_including(db_shard: 1, end_time: "2026-09-13T01:00:00Z"))
          end

          it "merges a single row of a multi-row query" do
            # A db_shard with a single row must not be mistaken for multiple rows
            result = range_lookup({ 0 => [[[1.0, nil], [3.0, nil], [10.0, nil]]], 1 => [[[2.0, nil], [10.0, nil]]] })
            expect(result).to eq([[1.0, nil], [2.0, nil], [3.0, nil]])
          end

          it "aligns the other db_shards to the rows of the first item's db_shard by packet time" do
            shard0 = [
              [[1.0, nil], [3.0, nil], [10.0, nil]],
              [[4.0, nil], [6.0, nil], [30.0, nil]],
              [[7.0, nil], [9.0, nil], [50.0, nil]],
            ]
            shard1 = [
              [[2.0, nil], [20.0, nil]],
              [[5.0, nil], [30.0, nil]],
              [[8.0, nil], [40.0, nil]],
              [[11.0, nil], [60.0, nil]],
            ]
            expected = [
              # No db_shard 1 row at or before time 10
              [[1.0, nil], [nil, nil], [3.0, nil]],
              # The db_shard 1 row at the same time 30
              [[4.0, nil], [5.0, nil], [6.0, nil]],
              # The last db_shard 1 row before time 50 (time 40) and never the later time 60
              [[7.0, nil], [8.0, nil], [9.0, nil]],
            ]
            expect(range_lookup({ 0 => shard0, 1 => shard1 })).to eq(expected)
          end

          it "seeds the other db_shards with their last row before start_time" do
            shard0 = [[[1.0, nil], [3.0, nil], [10.0, nil]], [[4.0, nil], [6.0, nil], [30.0, nil]]]
            seeds = { 0 => [[[0.0, nil], [0.0, nil], [-10.0, nil]]], 1 => [[[2.0, nil], [-5.0, nil]]] }
            result = range_lookup({ 0 => shard0, 1 => [[[5.0, nil], [20.0, nil]]] }, seeds: seeds)
            # Like ASOF JOIN the db_shard 1 row before start_time aligns to the driving row at time 10
            expect(result).to eq([[[1.0, nil], [2.0, nil], [3.0, nil]], [[4.0, nil], [5.0, nil], [6.0, nil]]])
            # Only the other db_shards are seeded, never the driving db_shard
            expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).with(anything, hash_including(db_shard: 1, end_time: nil))
            expect(QuestDBClient).not_to have_received(:tsdb_lookup_single_db_shard).with(anything, hash_including(db_shard: 0, end_time: nil))
          end

          it "drives the rows from the db_shard of the first item" do
            items.rotate!
            shard0 = [[[1.0, nil], [3.0, nil], [10.0, nil]], [[4.0, nil], [6.0, nil], [30.0, nil]]]
            result = range_lookup({ 0 => shard0, 1 => [[[5.0, nil], [30.0, nil]]] })
            # INST2 is now first so db_shard 1 drives a single row at time 30 and
            # db_shard 0 contributes its row at time 30 (never its time 10 row)
            expect(result).to eq([[5.0, nil], [4.0, nil], [6.0, nil]])
          end

          it "fills a db_shard with no results with nils" do
            result = range_lookup({ 0 => [[[1.0, nil], [3.0, nil], [10.0, nil]], [[4.0, nil], [6.0, nil], [30.0, nil]]], 1 => {} })
            expect(result).to eq([[[1.0, nil], [nil, nil], [3.0, nil]], [[4.0, nil], [nil, nil], [6.0, nil]]])
          end

          it "returns empty when the db_shard of the first item has no results" do
            expect(range_lookup({ 0 => {}, 1 => [[[2.0, nil], [10.0, nil]]] })).to eq({})
          end

          it "doesn't query a db_shard with only placeholders" do
            items[1] = ["INST2", "HEALTH_STATUS", nil, nil, nil]
            result = range_lookup({ 0 => [[[1.0, nil], [3.0, nil], [10.0, nil]], [[4.0, nil], [6.0, nil], [30.0, nil]]] })
            expect(result).to eq([[[1.0, nil], [nil, nil], [3.0, nil]], [[4.0, nil], [nil, nil], [6.0, nil]]])
            expect(QuestDBClient).not_to have_received(:tsdb_lookup_single_db_shard).with(anything, hash_including(db_shard: 1))
          end
        end
      end
    end

    describe "numeric_column_type?" do
      it "returns true for aggregatable numeric types (case-insensitive)" do
        ['BYTE', 'SHORT', 'INT', 'LONG', 'FLOAT', 'DOUBLE', 'double', 'float'].each do |type|
          expect(QuestDBClient.numeric_column_type?(type)).to be true
        end
      end

      it "returns false for non-numeric types and nil" do
        ['VARCHAR', 'SYMBOL', 'STRING', 'BOOLEAN', 'TIMESTAMP', nil].each do |type|
          expect(QuestDBClient.numeric_column_type?(type)).to be false
        end
      end
    end

    describe "build_aggregation_selects" do
      it "aggregates the raw column for RAW value type" do
        selects, mapping = QuestDBClient.build_aggregation_selects("TEMP1", :RAW)
        expect(selects).to eq([
          'min("TEMP1") as "TEMP1__N"',
          'max("TEMP1") as "TEMP1__X"',
          'avg("TEMP1") as "TEMP1__A"',
          'stddev("TEMP1") as "TEMP1__S"',
        ])
        expect(mapping["TEMP1__N"]).to eq(["TEMP1", :MIN, :RAW])
      end

      it "aggregates the __C column for CONVERTED value type" do
        selects, mapping = QuestDBClient.build_aggregation_selects("TEMP1", :CONVERTED)
        expect(selects).to eq([
          'min("TEMP1__C") as "TEMP1__CN"',
          'max("TEMP1__C") as "TEMP1__CX"',
          'avg("TEMP1__C") as "TEMP1__CA"',
          'stddev("TEMP1__C") as "TEMP1__CS"',
        ])
        expect(mapping["TEMP1__CN"]).to eq(["TEMP1", :MIN, :CONVERTED])
      end

      it "aggregates the __C column when it exists and is numeric" do
        existing = { "TEMP1" => "FLOAT", "TEMP1__C" => "DOUBLE", "TEMP1__F" => "VARCHAR" }
        selects, = QuestDBClient.build_aggregation_selects("TEMP1", :CONVERTED, existing_columns: existing)
        expect(selects.first).to eq('min("TEMP1__C") as "TEMP1__CN"')
      end

      # Items without a read_conversion (e.g. POSPROGRESS, which only has a format
      # string) have no __C column in the table. CONVERTED reduced queries must fall
      # back to the raw column rather than referencing a non-existent __C column.
      it "falls back to the raw column when the __C column does not exist" do
        existing = { "POSPROGRESS" => "FLOAT", "POSPROGRESS__F" => "VARCHAR" }
        selects, mapping = QuestDBClient.build_aggregation_selects("POSPROGRESS", :CONVERTED, existing_columns: existing)
        expect(selects).to eq([
          'min("POSPROGRESS") as "POSPROGRESS__CN"',
          'max("POSPROGRESS") as "POSPROGRESS__CX"',
          'avg("POSPROGRESS") as "POSPROGRESS__CA"',
          'stddev("POSPROGRESS") as "POSPROGRESS__CS"',
        ])
        # The mapping value type stays CONVERTED so the requested object still matches.
        expect(mapping["POSPROGRESS__CN"]).to eq(["POSPROGRESS", :MIN, :CONVERTED])
      end

      # States items store their converted value as a VARCHAR string, which can't be
      # aggregated with min/max/avg/stddev. Fall back to the raw (numeric) column.
      it "falls back to the raw column when the __C column is non-numeric (states VARCHAR)" do
        existing = { "MODE" => "INT", "MODE__C" => "VARCHAR" }
        selects, = QuestDBClient.build_aggregation_selects("MODE", :CONVERTED, existing_columns: existing)
        expect(selects.first).to eq('min("MODE") as "MODE__CN"')
      end

      it "uses the original item name in the mapping when provided" do
        selects, mapping = QuestDBClient.build_aggregation_selects("ARY", :RAW, item_name: "ARY[0]")
        expect(selects.first).to eq('min("ARY") as "ARY__N"')
        expect(mapping["ARY__N"]).to eq(["ARY[0]", :MIN, :RAW])
      end

      it "raises for FORMATTED value type since strings cannot be aggregated" do
        expect { QuestDBClient.build_aggregation_selects("STR", :FORMATTED) }
          .to raise_error(QuestDBClient::QuestDBError, /Unsupported value type/)
      end
    end

    describe "build_packet_reduced_selects" do
      let(:packet_def) do
        {
          "items" => [
            { "name" => "TEMP1", "data_type" => "FLOAT" },
            { "name" => "POSPROGRESS", "data_type" => "FLOAT" },
            { "name" => "LABEL", "data_type" => "STRING" }, # skipped, can't aggregate
          ],
        }
      end

      it "builds aggregations for numeric items and skips strings" do
        selects, has_items = QuestDBClient.build_packet_reduced_selects(packet_def, :RAW)
        expect(has_items).to be true
        expect(selects.first).to eq(QuestDBClient::TIMESTAMP_SELECT)
        expect(selects).to include('avg("TEMP1") as "TEMP1__A"')
        expect(selects).to include('avg("POSPROGRESS") as "POSPROGRESS__A"')
        expect(selects.join).to_not include("LABEL")
      end

      it "falls back to raw columns for CONVERTED when no numeric __C column exists" do
        existing = { "TEMP1" => "FLOAT", "TEMP1__C" => "DOUBLE", "POSPROGRESS" => "FLOAT" }
        selects, = QuestDBClient.build_packet_reduced_selects(packet_def, :CONVERTED, existing_columns: existing)
        # TEMP1 has a numeric __C column, POSPROGRESS does not
        expect(selects).to include('avg("TEMP1__C") as "TEMP1__CA"')
        expect(selects).to include('avg("POSPROGRESS") as "POSPROGRESS__CA"')
      end

      it "returns no items for an empty packet definition" do
        selects, has_items = QuestDBClient.build_packet_reduced_selects(nil, :RAW)
        expect(has_items).to be false
        expect(selects).to eq([QuestDBClient::TIMESTAMP_SELECT])
      end
    end
  end
end
