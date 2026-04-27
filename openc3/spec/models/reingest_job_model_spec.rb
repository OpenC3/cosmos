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
require 'openc3/models/reingest_job_model'

module OpenC3
  describe ReingestJobModel do
    before(:each) { mock_redis() }

    def build(name:, state: 'Queued', **kwargs)
      ReingestJobModel.new(name: name, state: state, scope: 'DEFAULT', **kwargs).tap(&:create)
    end

    describe '.names' do
      it 'lists job ids scoped to the requested scope' do
        build(name: 'job-a')
        build(name: 'job-b')
        expect(ReingestJobModel.names(scope: 'DEFAULT')).to match_array(['job-a', 'job-b'])
      end
    end

    describe '.all' do
      it 'returns models sorted by updated_at descending' do
        build(name: 'old')
        sleep 0.01 # updated_at is nsec-from-epoch; small delay ensures ordering
        build(name: 'new')
        ordered = ReingestJobModel.all(scope: 'DEFAULT')
        # `all` returns [[name, hash], ...] sorted newest-first
        expect(ordered.first.first).to eql('new')
        expect(ordered.last.first).to eql('old')
      end
    end

    describe '#stale?' do
      it 'is false for non-Running states regardless of age' do
        model = build(name: 'done', state: 'Complete')
        # Simulate an old heartbeat
        model.instance_variable_set(:@updated_at, (Time.now - 3600).to_nsec_from_epoch)
        expect(model.stale?).to be false
      end

      it 'is false for a fresh Running job' do
        model = build(name: 'fresh', state: 'Running')
        expect(model.stale?).to be false
      end

      it 'is true for a Running job whose heartbeat exceeds STALE_THRESHOLD_SEC' do
        model = build(name: 'stuck', state: 'Running')
        old_nsec = Time.now.to_nsec_from_epoch - (ReingestJobModel::STALE_THRESHOLD_SEC + 10) * 1_000_000_000
        model.instance_variable_set(:@updated_at, old_nsec)
        expect(model.stale?).to be true
      end
    end

    describe '#as_json' do
      it 'reports state as "Stale" when stale? is true' do
        model = build(name: 'stuck2', state: 'Running')
        old_nsec = Time.now.to_nsec_from_epoch - (ReingestJobModel::STALE_THRESHOLD_SEC + 10) * 1_000_000_000
        model.instance_variable_set(:@updated_at, old_nsec)
        expect(model.as_json['state']).to eql('Stale')
      end
    end
  end
end
