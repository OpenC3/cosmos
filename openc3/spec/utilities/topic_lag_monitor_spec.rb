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

require "spec_helper"
require "openc3/utilities/topic_lag_monitor"

module OpenC3
  describe TopicLagMonitor do
    TOPIC = "DEFAULT__DECOM__{INST}__HEALTH_STATUS"
    NOW = 1_000_000.0

    # Build a stream id written lag seconds before NOW + at
    def id_for(lag, at = 0, seq = 0)
      "#{((NOW + at - lag) * 1000).to_i}-#{seq}"
    end

    # Record a message read at NOW + at that is lag seconds old
    def rec(lag, at)
      monitor.record(TOPIC, id_for(lag, at), now: NOW + at)
    end

    let(:logger) { double("logger", info: nil, warn: nil, error: nil, debug: nil) }
    let(:metric) { double("metric", set: nil) }
    let(:store) { double("store") }
    let(:monitor) { TopicLagMonitor.new(name: "DEFAULT__DECOM__INST_INT", logger: logger, metric: metric, scope: "DEFAULT") }

    before(:each) do
      allow(EphemeralStore).to receive(:instance).and_return(store)
      allow(Store).to receive(:db_shard_for_target).and_return(0)
      allow(store).to receive(:xinfo).and_return({})
    end

    around(:each) do |example|
      saved = ENV.to_h.select { |k, _| k.start_with?('OPENC3_LAG_') }
      example.run
      ENV.delete_if { |k, _| k.start_with?('OPENC3_LAG_') }
      saved.each { |k, v| ENV[k] = v }
    end

    it "sets the gauge metric and returns the lag" do
      expect(metric).to receive(:set).with(name: 'decom_topic_delta_seconds', value: be_within(0.01).of(1.5), type: 'gauge', unit: 'seconds', help: 'help')
      lag = monitor.record(TOPIC, id_for(1.5), metric_name: 'decom_topic_delta_seconds', help: 'help', now: NOW)
      expect(lag).to be_within(0.01).of(1.5)
      expect(monitor.state).to eq(TopicLagMonitor::OK)
    end

    it "notifies when crossing the warning and critical thresholds" do
      expect(logger).to receive(:warn).with(/falling behind processing: 6.0s behind/, type: Logger::NOTIFICATION).once
      rec(6, 0)
      expect(monitor.state).to eq(TopicLagMonitor::WARN)
      # Still warning, no new notification
      rec(7, 1)

      expect(logger).to receive(:error).with(/falling behind processing: 31.0s behind/, type: Logger::NOTIFICATION).once
      rec(31, 2)
      expect(monitor.state).to eq(TopicLagMonitor::CRITICAL)
    end

    it "recovers only after staying below the clear threshold for the hold time" do
      rec(6, 0)
      expect(logger).to receive(:info).with(/has caught up processing \(max lag 6.0s\)/, type: Logger::NOTIFICATION).once
      # Below the warning threshold but not below warn * CLEAR_RATIO
      rec(4, 1)
      # Below the clear threshold but not held long enough
      rec(1, 2)
      rec(1, 11)
      # Lag bounces back up which restarts the hold time
      rec(3, 12)
      rec(1, 13)
      rec(1, 22)
      expect(monitor.state).to eq(TopicLagMonitor::WARN)
      rec(1, 23)
      expect(monitor.state).to eq(TopicLagMonitor::OK)
    end

    it "steps down from critical to warning without a recovery notification" do
      rec(40, 0)
      expect(logger).not_to receive(:info)
      rec(10, 1)
      rec(10, 11)
      expect(monitor.state).to eq(TopicLagMonitor::WARN)
    end

    it "rate limits repeated notifications while lagging" do
      expect(logger).to receive(:warn).twice
      rec(6, 0)
      rec(6, 100)
      rec(6, 299)
      rec(6, 300)
    end

    it "uses thresholds from the environment" do
      ENV['OPENC3_LAG_WARN_SECONDS'] = '20'
      ENV['OPENC3_LAG_CRITICAL_SECONDS'] = '60'
      expect(logger).not_to receive(:warn)
      rec(10, 0)
      expect(monitor.state).to eq(TopicLagMonitor::OK)
    end

    it "disables notifications when the warning threshold is zero" do
      ENV['OPENC3_LAG_WARN_SECONDS'] = '0'
      expect(logger).not_to receive(:warn)
      expect(logger).not_to receive(:error)
      expect(metric).to receive(:set)
      monitor.record(TOPIC, id_for(100), metric_name: 'm', help: 'h', now: NOW)
    end

    it "ignores invalid environment values" do
      ENV['OPENC3_LAG_WARN_SECONDS'] = 'abc'
      expect(logger).to receive(:warn).once
      rec(6, 0)
    end

    context "trimmed data detection" do
      it "does not check for trimmed data when not lagging" do
        expect(store).not_to receive(:xinfo)
        monitor.record(TOPIC, id_for(3), now: NOW)
        monitor.record(TOPIC, id_for(1), now: NOW)
      end

      it "does not check small gaps between messages" do
        expect(store).not_to receive(:xinfo)
        monitor.record(TOPIC, id_for(61), now: NOW)
        monitor.record(TOPIC, id_for(60.5), now: NOW)
      end

      it "alerts when data between messages was trimmed" do
        monitor.record(TOPIC, id_for(90), now: NOW)
        # Everything up through 40s ago was trimmed before we read it
        expect(store).to receive(:xinfo).with(:stream, TOPIC).and_return({ 'max-deleted-entry-id' => id_for(40) })
        expect(logger).to receive(:error).with(/data was trimmed before it was processed: #{Regexp.escape(TOPIC)} \(~50.0s\)/, type: Logger::ALERT)
        monitor.record(TOPIC, id_for(39), now: NOW)
      end

      it "does not alert when the deleted data had already been processed" do
        monitor.record(TOPIC, id_for(40), now: NOW)
        expect(store).to receive(:xinfo).and_return({ 'max-deleted-entry-id' => id_for(50) })
        expect(logger).not_to receive(:error).with(anything, type: Logger::ALERT)
        monitor.record(TOPIC, id_for(35), now: NOW)
      end

      it "aggregates and rate limits data skipped alerts" do
        topic2 = "DEFAULT__DECOM__{INST}__ADCS"
        monitor.record(TOPIC, id_for(90), now: NOW)
        monitor.record(topic2, id_for(90), now: NOW)
        allow(store).to receive(:xinfo).and_return({ 'max-deleted-entry-id' => id_for(40) })
        expect(logger).to receive(:error).with(/#{Regexp.escape(TOPIC)}/, type: Logger::ALERT).once
        monitor.record(TOPIC, id_for(39), now: NOW)
        # Second topic skip is held until the renotify interval passes
        monitor.record(topic2, id_for(39), now: NOW + 2)
        expect(logger).to receive(:error).with(/#{Regexp.escape(topic2)}/, type: Logger::ALERT).once
        monitor.record(topic2, id_for(38), now: NOW + 301)
      end

      it "rate limits xinfo checks per topic" do
        monitor.record(TOPIC, id_for(90), now: NOW)
        expect(store).to receive(:xinfo).once.and_return({})
        monitor.record(TOPIC, id_for(80), now: NOW)
        monitor.record(TOPIC, id_for(70), now: NOW + 0.5)
      end

      it "looks up the db_shard from the target hashtag" do
        monitor.record(TOPIC, id_for(90), now: NOW)
        expect(Store).to receive(:db_shard_for_target).with("INST", scope: "DEFAULT").and_return(2)
        expect(EphemeralStore).to receive(:instance).with(db_shard: 2).and_return(store)
        expect(store).to receive(:xinfo).and_return({})
        monitor.record(TOPIC, id_for(80), now: NOW)
      end

      it "handles servers without max-deleted-entry-id and xinfo errors" do
        monitor.record(TOPIC, id_for(90), now: NOW)
        expect(store).to receive(:xinfo).and_return({})
        monitor.record(TOPIC, id_for(80), now: NOW)
        expect(store).to receive(:xinfo).and_raise(RuntimeError.new("ERR no such key"))
        expect(logger).to receive(:debug).with(/unable to check/)
        monitor.record(TOPIC, id_for(70), now: NOW + 2)
      end
    end
  end
end
