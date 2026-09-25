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
            'decom_topic_delta_seconds' => { 'value' => 2.0, 'type' => 'gauge' },
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
    end

    it 'preserves aggregate metrics by default' do
      allow(MetricModel).to receive(:redis_metrics).and_return({})
      result = api.get_metrics(scope: 'TEST')
      expect(result['decom_total']).to eq(30)
      expect(result['decom_topic_delta_seconds']).to eq(5.0)
      expect(result).not_to have_key('TEST__DECOM__INST')
    end

    it 'returns scoped service metrics with timestamps and metadata when detailed' do
      expect(api).to receive(:authorize).with(permission: 'system', manual: true, scope: 'TEST', token: 'test-token')
      expect(MetricModel).not_to receive(:redis_metrics)
      expect(api.get_metrics(detailed: true, manual: true, scope: 'TEST', token: 'test-token')).to eq(metrics)
    end

    it 'authorizes before reading detailed metrics' do
      allow(api).to receive(:authorize).and_raise('Unauthorized')
      expect(MetricModel).not_to receive(:all)
      expect { api.get_metrics(detailed: true, scope: 'TEST') }.to raise_error('Unauthorized')
    end

    it 'returns an empty object when no detailed metrics have been reported' do
      allow(MetricModel).to receive(:all).with(scope: 'TEST').and_return({})
      expect(api.get_metrics(detailed: true, scope: 'TEST')).to eq({})
    end
  end
end
