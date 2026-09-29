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

require 'spec_helper'
require 'openc3/operators/operator'
require 'openc3/models/metric_model'

module OpenC3
  describe Operator do
    before(:each) do
      mock_redis()
      allow(ProcessStats).to receive(:supported?).and_return(true)
    end

    def sampler(pid:, sampled: true, cpu: 0.25)
      double(
        "ProcessStats",
        pid: pid,
        sample: sampled,
        values: {
          'average_cpu_utilization' => { 'value' => cpu, 'type' => 'gauge', 'unit' => 'ratio' },
          'resident_memory_bytes' => { 'value' => 1024.0, 'type' => 'gauge', 'unit' => 'bytes' },
        }
      )
    end

    def process(pid:, scope: 'DEFAULT')
      double("OperatorProcess", pid: pid, scope: scope)
    end

    describe "publish_process_metrics" do
      # The whole point: a microservice that exec()s into a Rails app or a
      # python script never loads the OpenC3 libraries, so it can never report
      # its own cpu. The operator knows its pid and reports for it.
      it "reports process metrics for a microservice that cannot report for itself" do
        allow(ProcessStats).to receive(:new).with(1234).and_return(sampler(pid: 1234))

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        operator.publish_process_metrics

        values = MetricModel.all(scope: 'DEFAULT')['DEFAULT__USER__CFDP']['values']
        expect(values['average_cpu_utilization']['value']).to eql(0.25)
        expect(values['resident_memory_bytes']['value']).to eql(1024.0)
      end

      it "keeps one sampler per microservice so cpu deltas accumulate" do
        stats = sampler(pid: 1234)
        expect(ProcessStats).to receive(:new).with(1234).once.and_return(stats)

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        3.times { operator.publish_process_metrics }
      end

      it "starts a fresh sampler when the microservice respawns under a new pid" do
        first = sampler(pid: 1234)
        second = sampler(pid: 5678, cpu: 0.5)
        allow(ProcessStats).to receive(:new).with(1234).and_return(first)
        allow(ProcessStats).to receive(:new).with(5678).and_return(second)

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        operator.publish_process_metrics

        # Respawn: the old cpu totals belong to a process that no longer exists
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 5678)
        operator.publish_process_metrics

        values = MetricModel.all(scope: 'DEFAULT')['DEFAULT__USER__CFDP']['values']
        expect(values['average_cpu_utilization']['value']).to eql(0.5)
      end

      it "skips a process that has not been started yet" do
        expect(ProcessStats).not_to receive(:new)

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: nil)
        operator.publish_process_metrics
      end

      it "publishes nothing when the sample fails" do
        allow(ProcessStats).to receive(:new).with(1234).and_return(sampler(pid: 1234, sampled: false))

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        operator.publish_process_metrics

        expect(MetricModel.all(scope: 'DEFAULT')['DEFAULT__USER__CFDP']).to be_nil
      end

      it "stops tracking microservices that go away" do
        allow(ProcessStats).to receive(:new).with(1234).and_return(sampler(pid: 1234))

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        operator.publish_process_metrics
        expect(operator.instance_variable_get(:@process_stats).keys).to eql(['DEFAULT__USER__CFDP'])

        operator.processes.delete('DEFAULT__USER__CFDP')
        operator.publish_process_metrics
        expect(operator.instance_variable_get(:@process_stats)).to be_empty
      end

      it "does nothing on a platform without procfs" do
        allow(ProcessStats).to receive(:supported?).and_return(false)
        expect(ProcessStats).not_to receive(:new)

        operator = Operator.new
        operator.processes['DEFAULT__USER__CFDP'] = process(pid: 1234)
        operator.publish_process_metrics
      end
    end
  end
end
