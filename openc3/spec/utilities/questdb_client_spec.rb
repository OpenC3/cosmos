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
        # Base time for the db_shard tests. Table times are in seconds after it.
        let(:base_ns) { 1_789_257_600_000_000_000 } # 2026-09-13T00:00:00Z
        # Target name => db_shard
        let(:db_shards) { { "INST" => 0, "INST2" => 1 } }
        # [target_name, packet_name] => [[seconds, { item_name => value }]]
        let(:tables) do
          {
            ["INST", "HEALTH_STATUS"] => [[10, { "TEMP1" => 1, "TEMP2" => 2 }], [30, { "TEMP1" => 3, "TEMP2" => 4 }], [50, { "TEMP1" => 5, "TEMP2" => 6 }]],
            ["INST2", "HEALTH_STATUS"] => [[20, { "TEMP1" => 20 }], [30, { "TEMP1" => 30 }], [40, { "TEMP1" => 40 }], [60, { "TEMP1" => 60 }]],
            # Only a row before the start of the range lookups
            ["INST2", "EARLY"] => [[0, { "TEMP1" => 0 }]],
            # A row between the last two INST2 HEALTH_STATUS rows in the range lookups
            ["INST2", "LATER"] => [[45, { "TEMP1" => 45 }]],
          }
        end

        before(:each) do
          allow(QuestDBClient).to receive(:db_shard_for_target) { |target_name, **| db_shards.fetch(target_name, 0) }
          @queries = []
          allow(QuestDBClient).to receive(:tsdb_lookup_single_db_shard) { |items, **kwargs| fake_single_db_shard(items, **kwargs) }
        end

        def iso(seconds)
          QuestDBClient.nsec_to_iso(base_ns + (seconds * 1_000_000_000))
        end

        def iso_to_nsec(value)
          seconds, fraction = value.delete_suffix("Z").split(".")
          (Time.strptime("#{seconds}Z", "%Y-%m-%dT%H:%M:%S%z").to_i * 1_000_000_000) + fraction.ljust(9, "0").to_i
        end

        def table_rows(target_name, packet_name)
          tables.fetch([target_name, packet_name]).map { |seconds, values| [base_ns + (seconds * 1_000_000_000), values] }
        end

        # Stands in for one QuestDB query: the first packet (T0) is filtered by time and
        # every other packet is ASOF JOINed to it, using its last row at or before each T0 row
        def fake_single_db_shard(items, start_time:, end_time: nil, db_shard: 0, flatten: true, inclusive: false, with_time: false, **)
          expect(flatten).to be false
          @queries << [db_shard, items.map { |item| item[1] }]
          real_items = items.select { |item| item[2] }
          real_items.each { |item| expect(db_shards[item[0]]).to eq(db_shard), "#{item[0]} queried on db_shard #{db_shard}" }
          start = iso_to_nsec(start_time)
          rows = table_rows(real_items[0][0], real_items[0][1])
          if end_time
            rows = rows.select { |time, _| time >= start and time < iso_to_nsec(end_time) }
          else
            rows = rows.select { |time, _| time < start or (inclusive and time == start) }.last(1)
          end

          result = rows.map do |time, _|
            row = items.map do |item|
              next [nil, nil] unless item[2]
              next [time / 1_000_000_000.0, nil] if item[2] == "PACKET_TIMESECONDS"

              joined = table_rows(item[0], item[1]).select { |joined_time, _| joined_time <= time }
              [joined.empty? ? nil : joined[-1][1][item[2]], nil]
            end
            row << [time, nil] if with_time
            row
          end
          result.empty? ? {} : result
        end

        # Items are "TARGET PACKET ITEM", or "TARGET PACKET" for a placeholder
        def lookup(items, start, finish = nil)
          items = items.map do |item|
            parts = item.split
            parts.length == 3 ? parts + ["CONVERTED", nil] : parts + [nil, nil, nil]
          end
          QuestDBClient.tsdb_lookup(items, start_time: iso(start), end_time: finish && iso(finish))
        end

        it "uses the single db_shard fast path" do
          items = [["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", nil], ["INST", "HEALTH_STATUS", "TEMP2", "CONVERTED", nil]]
          allow(QuestDBClient).to receive(:tsdb_lookup_single_db_shard).and_return("result")
          expect(QuestDBClient.tsdb_lookup(items, start_time: iso(0), scope: "OTHER")).to eq("result")
          expect(QuestDBClient).to have_received(:tsdb_lookup_single_db_shard).once.with(items, hash_including(db_shard: 0, scope: "OTHER"))
        end

        it "aligns the other db_shards to the first item's db_shard by packet time" do
          expected = [
            # No INST2 row at or before 10 seconds
            [[1, nil], [nil, nil], [2, nil]],
            # The INST2 row at the same time
            [[3, nil], [30, nil], [4, nil]],
            # The last INST2 row before 50 seconds and never the later 60 second row
            [[5, nil], [40, nil], [6, nil]],
          ]
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST HEALTH_STATUS TEMP2"], 5, 55)).to eq(expected)
        end

        it "drives the rows from the db_shard of the first item" do
          expected = [[[20, nil], [1, nil]], [[30, nil], [3, nil]], [[40, nil], [3, nil]]]
          expect(lookup(["INST2 HEALTH_STATUS TEMP1", "INST HEALTH_STATUS TEMP1"], 5, 55)).to eq(expected)
        end

        it "carries forward a row before start_time" do
          expected = [[[1, nil], [0, nil]], [[3, nil], [0, nil]], [[5, nil], [0, nil]]]
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 EARLY TEMP1"], 5, 55)).to eq(expected)
        end

        it "aligns each packet on a db_shard independently" do
          items = ["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST2 LATER TEMP1"]
          # INST2 LATER is aligned to INST at 50 seconds, not INST2 HEALTH_STATUS at 40 seconds
          expected = [
            [[1, nil], [nil, nil], [nil, nil]],
            [[3, nil], [30, nil], [nil, nil]],
            [[5, nil], [40, nil], [45, nil]],
          ]
          expect(lookup(items, 5, 55)).to eq(expected)
          expect(lookup(items, 55)).to eq([[5, nil], [40, nil], [45, nil]])
          # Each packet on another db_shard is queried on its own
          expect(@queries.select { |db_shard, _| db_shard == 1 }.map(&:last).uniq).to contain_exactly(["HEALTH_STATUS"], ["LATER"])
        end

        it "returns the last row at or before the driving row" do
          # INST drives at 50 seconds so INST2 returns its 40 second row, not its 60 second row
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 70)).to eq([[5, nil], [40, nil]])
          # Including a row at the same time as the driving row
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 31)).to eq([[3, nil], [30, nil]])
        end

        it "returns a single row as a flat array" do
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 25, 35)).to eq([[3, nil], [30, nil]])
        end

        it "fills another db_shard with no rows with nils" do
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 5, 15)).to eq([[1, nil], [nil, nil]])
        end

        it "returns empty when the db_shard of the first item has no rows" do
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 55, 58)).to eq({})
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 5)).to eq({})
        end

        it "doesn't query a db_shard with only placeholders" do
          expect(lookup(["INST2 HEALTH_STATUS", "INST HEALTH_STATUS TEMP1", "INST2 LATER"], 25, 35)).to eq([[nil, nil], [3, nil], [nil, nil]])
          expect(@queries).to eq([[0, ["HEALTH_STATUS"]]])
        end

        it "doesn't query the placeholders on another db_shard" do
          expect(lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST2 LATER"], 25, 35)).to eq([[3, nil], [30, nil], [nil, nil]])
          expect(@queries).not_to include([1, ["LATER"]])
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
