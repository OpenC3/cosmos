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
require 'openc3/models/script_lifecycle_model'

module OpenC3
  describe ScriptLifecycleModel, type: :model do
    before(:each) do
      mock_redis()
    end

    let(:scope) { 'DEFAULT' }
    let(:name) { 'INST/procedures/test.rb' }
    let(:v1) { '01KQW7ZHJGQZK9Q3QVZNHQQ287' }
    let(:v2) { '01KQW7ZHY72RW7SH3F2YPDKKJK' }
    let(:v3) { '01KQW7ZJ9X70B4MEYS9WS1V3ZK' }

    describe '.get_or_build' do
      it 'returns an empty model when nothing is persisted' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
        expect(model.versions).to eq({})
        expect(model.latest_version_id).to be_nil
        expect(model.latest_state).to eq('unknown')
      end

      it 'rehydrates a persisted model' do
        ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
        rehydrated = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
        expect(rehydrated.latest_version_id).to eq(v1)
        expect(rehydrated.versions[v1]['saved_by']).to eq('alice')
      end
    end

    describe 'state derivation' do
      it 'returns new for a fresh save' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
        expect(model.latest_state).to eq('new')
        expect(model.locked_for_review?).to be(false)
      end

      it 'returns validated after record_validation' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_validation(version_id: v1)
        expect(model.latest_state).to eq('validated')
        expect(model.locked_for_review?).to be(false)
      end

      it 'returns reviewed after record_review and locks the script' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_validation(version_id: v1)
          .record_review(version_id: v1, username: 'bob', notes: 'looks good')
        expect(model.latest_state).to eq('reviewed')
        expect(model.locked_for_review?).to be(true)
        expect(model.versions[v1]['reviewed_by']).to eq('bob')
        expect(model.versions[v1]['reviewed_notes']).to eq('looks good')
      end
    end

    describe '#record_save' do
      it 'advances latest_version_id with each new version' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
        model.record_save(version_id: v1, username: 'alice')
        model.record_save(version_id: v2, username: 'bob')
        expect(model.latest_version_id).to eq(v2)
        expect(model.versions.keys).to contain_exactly(v1, v2)
      end

      it 'preserves prior versions immutably' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_validation(version_id: v1)
          .record_save(version_id: v2, username: 'alice')
        expect(model.versions[v1]['validated_at']).not_to be_nil
        expect(model.versions[v2]['validated_at']).to be_nil
      end
    end

    describe '#record_taint' do
      it 'flags the new version with provenance from the prior reviewed version' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_review(version_id: v1, username: 'bob')
          .record_taint(version_id: v2, username: 'alice', prev_version_id: v1, prev_reviewer: 'bob')
        expect(model.latest_version_id).to eq(v2)
        expect(model.versions[v2]['tainted']).to be(true)
        expect(model.versions[v2]['tainted_from_version_id']).to eq(v1)
        expect(model.versions[v2]['tainted_from_reviewed_by']).to eq('bob')
        expect(model.locked_for_review?).to be(false)
      end

      it 'leaves the prior reviewed version reviewed' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_review(version_id: v1, username: 'bob')
          .record_taint(version_id: v2, username: 'alice', prev_version_id: v1, prev_reviewer: 'bob')
        expect(model.state_of(v1)).to eq('reviewed')
      end
    end

    describe 'review of a tainted version cleans it' do
      it 'flips state to reviewed even though tainted flag remains' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_review(version_id: v1, username: 'bob')
          .record_taint(version_id: v2, username: 'alice', prev_version_id: v1, prev_reviewer: 'bob')
          .record_validation(version_id: v2)
          .record_review(version_id: v2, username: 'bob', notes: 're-reviewed after edit')
        expect(model.latest_state).to eq('reviewed')
        expect(model.locked_for_review?).to be(true)
        expect(model.versions[v2]['tainted']).to be(true)
        expect(model.versions[v2]['reviewed_by']).to eq('bob')
      end
    end

    describe '#record_review (multiple reviews allowed)' do
      it 'overwrites prior review fields with the latest sign-off' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_review(version_id: v1, username: 'bob', notes: 'first pass')
          .record_review(version_id: v1, username: 'carol', notes: 'second pass')
        expect(model.versions[v1]['reviewed_by']).to eq('carol')
        expect(model.versions[v1]['reviewed_notes']).to eq('second pass')
      end
    end

    describe '#record_execution' do
      it 'appends connected and disconnect runs as separate events' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_execution(version_id: v1, username: 'alice', disconnect: true)
          .record_execution(version_id: v1, username: 'alice', disconnect: false)
        execs = model.versions[v1]['executions']
        expect(execs.size).to eq(2)
        expect(execs[0]['type']).to eq('executed_disconnect')
        expect(execs[1]['type']).to eq('executed')
      end
    end

    describe '#record_restore' do
      it 'creates a new version with restored_from pointer' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_save(version_id: v2, username: 'bob')
          .record_restore(version_id: v3, username: 'alice', restored_from_version_id: v1)
        expect(model.latest_version_id).to eq(v3)
        expect(model.versions[v3]['restored_from_version_id']).to eq(v1)
      end
    end

    describe 'transitions on missing versions are no-ops' do
      it 'does not crash when validating a version that was never saved' do
        model = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_validation(version_id: v1)
        expect(model.versions).to eq({})
      end
    end

    describe 'JSON round-trip' do
      it 'preserves all fields through save and reload' do
        ScriptLifecycleModel.get_or_build(name: name, scope: scope)
          .record_save(version_id: v1, username: 'alice')
          .record_validation(version_id: v1)
          .record_review(version_id: v1, username: 'bob', notes: 'ok')
          .record_execution(version_id: v1, username: 'alice', disconnect: false)
          .record_taint(version_id: v2, username: 'alice', prev_version_id: v1, prev_reviewer: 'bob')

        rehydrated = ScriptLifecycleModel.get_or_build(name: name, scope: scope)
        expect(rehydrated.latest_version_id).to eq(v2)
        expect(rehydrated.versions[v1]['validated_at']).not_to be_nil
        expect(rehydrated.versions[v1]['reviewed_by']).to eq('bob')
        expect(rehydrated.versions[v1]['executions'].size).to eq(1)
        expect(rehydrated.versions[v2]['tainted']).to be(true)
      end
    end
  end
end
