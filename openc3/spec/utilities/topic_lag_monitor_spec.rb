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
    OTHER_TOPIC = "DEFAULT__DECOM__{INST}__ADCS"
    NOW = 1_000_000.0 # Start of a gauge window

    # Build a stream id written lag seconds before NOW + at
    def id_for(lag, at = 0, seq = 0)
      "#{((NOW + at - lag) * 1000).to_i}-#{seq}"
    end

    # Record a message read at NOW + at that is lag seconds old
    def rec(lag, at, topic = TOPIC)
      monitor.record(topic, id_for(lag, at), now: NOW + at)
    end

    # Record a message with the gauge metric enabled
    def rec_gauge(lag, at)
      monitor.record(TOPIC, id_for(lag, at), metric_name: 'm', help: 'h', now: NOW + at)
    end

    let(:logger) { double("logger", info: nil, warn: nil, error: nil, debug: nil) }
    let(:metric) { double("metric", set: nil) }
    let(:monitor) { TopicLagMonitor.new(name: "DEFAULT__DECOM__INST_INT", logger: logger, metric: metric) }

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
      expect(logger).to receive(:info).with(/has caught up processing \(max lag 6.0s on #{Regexp.escape(TOPIC)}\)/, type: Logger::NOTIFICATION).once
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

    it "names the lagging topic and the topic with the max lag" do
      expect(logger).to receive(:warn).with("DEFAULT__DECOM__INST_INT is falling behind processing: 6.0s behind on #{TOPIC} (max 6.0s on #{TOPIC})", type: Logger::NOTIFICATION)
      rec(6, 0)
      expect(logger).to receive(:error).with("DEFAULT__DECOM__INST_INT is falling behind processing: 31.0s behind on #{OTHER_TOPIC} (max 31.0s on #{OTHER_TOPIC})", type: Logger::NOTIFICATION)
      rec(31, 1, OTHER_TOPIC)
      expect(logger).to receive(:info).with("DEFAULT__DECOM__INST_INT has caught up processing (max lag 31.0s on #{OTHER_TOPIC})", type: Logger::NOTIFICATION)
      rec(1, 2)
      rec(1, 12)
      expect(monitor.state).to eq(TopicLagMonitor::OK)
    end

    context "falling behind again after recovering" do
      # Warn at 0 and recover at 11
      def warn_and_recover
        rec(6, 0)
        rec(1, 1)
        rec(1, 11)
        expect(monitor.state).to eq(TopicLagMonitor::OK)
      end

      it "does not renotify or announce recovery within the renotify interval" do
        expect(logger).to receive(:warn).once
        expect(logger).to receive(:info).once
        warn_and_recover
        rec(6, 20)
        expect(monitor.state).to eq(TopicLagMonitor::WARN)
        rec(1, 21)
        rec(1, 31)
        expect(monitor.state).to eq(TopicLagMonitor::OK)
      end

      it "notifies again after the renotify interval" do
        expect(logger).to receive(:warn).twice
        warn_and_recover
        rec(6, 300)
      end

      it "renotifies a continued episode once the renotify interval passes" do
        expect(logger).to receive(:warn).twice
        expect(logger).to receive(:info).twice
        warn_and_recover
        rec(6, 20)
        rec(6, 300)
        rec(1, 301)
        rec(1, 311)
      end

      it "always notifies an escalation past the last notified level" do
        expect(logger).to receive(:error).with(/31.0s behind/, type: Logger::NOTIFICATION).once
        warn_and_recover
        rec(31, 20)
        expect(monitor.state).to eq(TopicLagMonitor::CRITICAL)
      end
    end

    context "gauge metric" do
      it "reports the max lag within a window" do
        expect(metric).to receive(:set).with(hash_including(value: be_within(0.01).of(3))).once.ordered
        expect(metric).to receive(:set).with(hash_including(value: be_within(0.01).of(4))).once.ordered
        rec_gauge(3, 0)
        rec_gauge(1, 1) # Lower lag doesn't change the reported max
        rec_gauge(4, 2)
      end

      it "holds the previous window's max through the next window" do
        rec_gauge(4, 0)
        expect(metric).to receive(:set).with(hash_including(value: be_within(0.01).of(4))).once.ordered
        expect(metric).to receive(:set).with(hash_including(value: be_within(0.01).of(1))).once.ordered
        rec_gauge(1, 5)
        rec_gauge(1, 10)
      end

      it "does not hold the max across an idle window" do
        rec_gauge(4, 0)
        expect(metric).to receive(:set).with(hash_including(value: be_within(0.01).of(1)))
        rec_gauge(1, 12)
      end

      it "tracks each metric name separately" do
        monitor.record(TOPIC, id_for(4), metric_name: 'a', help: 'h', now: NOW)
        expect(metric).to receive(:set).with(hash_including(name: 'b', value: be_within(0.01).of(1)))
        monitor.record(TOPIC, id_for(1), metric_name: 'b', help: 'h', now: NOW)
      end
    end
  end
end
