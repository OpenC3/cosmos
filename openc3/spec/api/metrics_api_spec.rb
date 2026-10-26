# encoding: ascii-8bit
# Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md.

require 'spec_helper'
require 'openc3/api/metrics_api'

module OpenC3
  describe Api do
    let(:api) { Class.new { include Api }.new }
    let(:metrics) do
      {
        'TEST__DECOM__INST' => {
          'updated_at' => 1_800_000_000_000_000_000,
          'values' => {
            'decom_topic_delta_seconds' => { 'value' => 2.0, 'type' => 'gauge', 'help' => 'Delta time' },
            'decom_total' => { 'value' => 10, 'type' => 'counter' }
          }
        },
        'TEST__DECOM1__INST' => {
          'values' => {
            'decom_topic_delta_seconds' => { 'value' => 5.0, 'type' => 'gauge' },
            'decom_total' => { 'value' => 20, 'type' => 'counter' }
          }
        }
      }
    end

    before do
      allow(api).to receive(:authorize)
      allow(MetricModel).to receive(:all).with(scope: 'TEST').and_return(metrics)
      allow(MetricModel).to receive(:all_self_reported).with(scope: 'TEST').and_return(metrics)
    end

    it 'preserves aggregate metrics by default' do
      allow(MetricModel).to receive(:redis_metrics).and_return({})
      result = api.get_metrics(scope: 'TEST')
      expect(result['decom_total']).to eq(30)
      expect(result['decom_topic_delta_seconds']).to eq(5.0)
      expect(result).not_to have_key('TEST__DECOM__INST')
    end

    it 'returns scoped service flow metrics with timestamps when detailed' do
      expect(api).to receive(:authorize).with(permission: 'system', manual: true, scope: 'TEST', token: 'test-token')
      expect(MetricModel).not_to receive(:redis_metrics)
      expect(MetricModel).not_to receive(:all)
      expect(api.get_metrics(detailed: true, manual: true, scope: 'TEST', token: 'test-token')['services']).to eq(
        {
          'TEST__DECOM__INST' => {
            'updated_at' => 1_800_000_000_000_000_000,
            'values' => { 'decom_topic_delta_seconds' => { 'value' => 2.0 }, 'decom_total' => { 'value' => 10 } }
          },
          'TEST__DECOM1__INST' => {
            'updated_at' => nil,
            'values' => { 'decom_topic_delta_seconds' => { 'value' => 5.0 }, 'decom_total' => { 'value' => 20 } }
          }
        }
      )
    end

    it 'drops metrics Data Flows does not display and services with none left' do
      allow(MetricModel).to receive(:all_self_reported).with(scope: 'TEST').and_return(
        {
          'TEST__INTERFACE__INST_INT' => {
            'updated_at' => 1,
            'values' => {
              'interface_read_queue_bytes' => { 'value' => 1024, 'help' => 'Bytes' },
              'interface_tlm_total' => { 'value' => 3 },
              'resident_memory_bytes' => { 'value' => 1000 }
            }
          },
          'TEST__SCOPEMULTI__TEST' => { 'updated_at' => 1, 'values' => { 'some_gauge' => { 'value' => 1 } } },
          'TEST__EMPTY__X' => { 'updated_at' => 1 }
        }
      )
      expect(api.get_metrics(detailed: true, scope: 'TEST')['services']).to eq(
        {
          'TEST__INTERFACE__INST_INT' => {
            'updated_at' => 1,
            'values' => {
              'interface_read_queue_bytes' => { 'value' => 1024 },
              'interface_tlm_total' => { 'value' => 3 }
            }
          }
        }
      )
    end

    it 'authorizes before reading detailed metrics' do
      allow(api).to receive(:authorize).and_raise('Unauthorized')
      expect(MetricModel).not_to receive(:all)
      expect(MetricModel).not_to receive(:all_self_reported)
      expect { api.get_metrics(detailed: true, scope: 'TEST') }.to raise_error('Unauthorized')
    end

    it 'returns no services when no detailed metrics have been reported' do
      allow(MetricModel).to receive(:all_self_reported).with(scope: 'TEST').and_return({})
      expect(api.get_metrics(detailed: true, scope: 'TEST')['services']).to eq({})
    end

    it 'returns the lag notification thresholds when detailed' do
      expect(api.get_metrics(detailed: true, scope: 'TEST')['lag_thresholds']).to eq({ 'warning' => 5.0, 'critical' => 30.0 })
      stub_const('ENV', ENV.to_h.merge('OPENC3_LAG_WARN_SECONDS' => '2', 'OPENC3_LAG_CRITICAL_SECONDS' => '12.5'))
      expect(api.get_metrics(detailed: true, scope: 'TEST')['lag_thresholds']).to eq({ 'warning' => 2.0, 'critical' => 12.5 })
    end
  end
end
