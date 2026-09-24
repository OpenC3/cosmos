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

        def lookup(results, end_time: nil)
          # INST is on db_shard 0 and INST2 is on db_shard 1
          allow(QuestDBClient).to receive(:db_shard_for_target) { |target_name, **| target_name == "INST2" ? 1 : 0 }
          allow(QuestDBClient).to receive(:tsdb_lookup_single_db_shard) do |_items, db_shard:, flatten:, **|
            expect(flatten).to be false
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

        it "merges a single row of a multi-row query" do
          # A db_shard with a single row must not be mistaken for multiple rows
          result = lookup({ 0 => [[[1.0, nil], [3.0, nil]]], 1 => [[[2.0, nil]]] }, end_time: "2026-09-13T01:00:00Z")
          expect(result).to eq([[1.0, nil], [2.0, nil], [3.0, nil]])
        end

        it "merges multiple rows filling missing rows with nils" do
          result = lookup({ 0 => [[[1.0, nil], [3.0, nil]], [[4.0, nil], [6.0, nil]]], 1 => [[[2.0, nil]]] }, end_time: "2026-09-13T01:00:00Z")
          expect(result).to eq([[[1.0, nil], [2.0, nil], [3.0, nil]], [[4.0, nil], [nil, nil], [6.0, nil]]])
        end

        it "fills a db_shard with no results with nils" do
          expect(lookup({ 0 => [[[1.0, nil], [3.0, nil]]], 1 => {} })).to eq([[1.0, nil], [nil, nil], [3.0, nil]])
        end

        it "returns empty when no db_shard has results" do
          expect(lookup({ 0 => {}, 1 => {} }, end_time: "2026-09-13T01:00:00Z")).to eq({})
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
