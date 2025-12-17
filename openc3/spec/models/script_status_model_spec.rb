# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/script_status_model'

module OpenC3
  describe ScriptStatusModel, type: :model do
    before(:each) do
      mock_redis()
    end

    def generate_script_status(
      name: 'test_script',
      state: 'running',
      filename: 'test.rb',
      username: 'testuser',
      user_full_name: 'Test User',
      start_time: Time.now.utc.iso8601,
      scope: 'DEFAULT',
      **kwargs
    )
      ScriptStatusModel.new(
        name: name,
        state: state,
        filename: filename,
        username: username,
        user_full_name: user_full_name,
        start_time: start_time,
        scope: scope,
        **kwargs
      )
    end

    describe "initialize" do
      it "creates a new running script status" do
        model = generate_script_status()
        expect(model).to be_a(ScriptStatusModel)
        expect(model.state).to eq('running')
        expect(model.filename).to eq('test.rb')
        expect(model.username).to eq('testuser')
        expect(model.shard).to eq(0)
      end

      it "creates a completed script status" do
        model = generate_script_status(state: 'completed', end_time: Time.now.utc.iso8601)
        expect(model).to be_a(ScriptStatusModel)
        expect(model.state).to eq('completed')
        expect(model.is_complete?).to be true
      end

      it "converts shard to integer" do
        model = generate_script_status(shard: "2")
        expect(model.shard).to eq(2)
      end

      it "sets all optional attributes" do
        model = generate_script_status(
          current_filename: 'current.rb',
          line_no: 42,
          start_line_no: 1,
          end_line_no: 100,
          end_time: Time.now.utc.iso8601,
          disconnect: true,
          environment: { 'VAR' => 'value' },
          suite_runner: 'suite1',
          errors: ['error1', 'error2'],
          pid: 12345,
          log: '/path/to/log',
          report: '/path/to/report',
          script_engine: 'ruby'
        )
        expect(model.current_filename).to eq('current.rb')
        expect(model.line_no).to eq(42)
        expect(model.start_line_no).to eq(1)
        expect(model.end_line_no).to eq(100)
        expect(model.disconnect).to be true
        expect(model.environment).to eq({ 'VAR' => 'value' })
        expect(model.suite_runner).to eq('suite1')
        expect(model.errors).to eq(['error1', 'error2'])
        expect(model.pid).to eq(12345)
        expect(model.log).to eq('/path/to/log')
        expect(model.report).to eq('/path/to/report')
        expect(model.script_engine).to eq('ruby')
      end
    end

    describe "id" do
      it "returns the name as id" do
        model = generate_script_status(name: 'my_script')
        expect(model.id).to eq('my_script')
      end
    end

    describe "is_complete?" do
      it "returns true for completed state" do
        model = generate_script_status(state: 'completed')
        expect(model.is_complete?).to be true
      end

      it "returns true for completed_errors state" do
        model = generate_script_status(state: 'completed_errors')
        expect(model.is_complete?).to be true
      end

      it "returns true for stopped state" do
        model = generate_script_status(state: 'stopped')
        expect(model.is_complete?).to be true
      end

      it "returns true for crashed state" do
        model = generate_script_status(state: 'crashed')
        expect(model.is_complete?).to be true
      end

      it "returns true for killed state" do
        model = generate_script_status(state: 'killed')
        expect(model.is_complete?).to be true
      end

      it "returns false for running state" do
        model = generate_script_status(state: 'running')
        expect(model.is_complete?).to be false
      end

      it "returns false for spawning state" do
        model = generate_script_status(state: 'spawning')
        expect(model.is_complete?).to be false
      end

      it "returns false for paused state" do
        model = generate_script_status(state: 'paused')
        expect(model.is_complete?).to be false
      end

      it "returns false for waiting state" do
        model = generate_script_status(state: 'waiting')
        expect(model.is_complete?).to be false
      end

      it "returns false for breakpoint state" do
        model = generate_script_status(state: 'breakpoint')
        expect(model.is_complete?).to be false
      end

      it "returns false for error state" do
        model = generate_script_status(state: 'error')
        expect(model.is_complete?).to be false
      end
    end

    describe "state=" do
      it "updates state when not complete" do
        model = generate_script_status(state: 'running')
        model.state = 'paused'
        expect(model.state).to eq('paused')
      end

      it "changes to completed_errors when errors exist" do
        model = generate_script_status(state: 'running', errors: ['error1'])
        model.state = 'completed'
        expect(model.state).to eq('completed_errors')
      end

      it "does not change state when already complete" do
        model = generate_script_status(state: 'completed')
        model.state = 'running'
        expect(model.state).to eq('completed')
      end

      it "does not override existing complete state" do
        model = generate_script_status(state: 'crashed')
        model.state = 'completed'
        expect(model.state).to eq('crashed')
      end
    end

    describe "self.get" do
      it "retrieves a running script" do
        model = generate_script_status(name: 'script1')
        model.create()
        retrieved = ScriptStatusModel.get(name: 'script1', scope: 'DEFAULT', type: 'running')
        expect(retrieved).not_to be_nil
        expect(retrieved['name']).to eq('script1')
        expect(retrieved['state']).to eq('running')
      end

      it "retrieves a completed script" do
        model = generate_script_status(name: 'script2', state: 'completed')
        model.create()
        retrieved = ScriptStatusModel.get(name: 'script2', scope: 'DEFAULT', type: 'completed')
        expect(retrieved).not_to be_nil
        expect(retrieved['name']).to eq('script2')
        expect(retrieved['state']).to eq('completed')
      end

      it "checks running first with auto type" do
        model = generate_script_status(name: 'script3')
        model.create()
        retrieved = ScriptStatusModel.get(name: 'script3', scope: 'DEFAULT', type: 'auto')
        expect(retrieved).not_to be_nil
        expect(retrieved['name']).to eq('script3')
      end

      it "returns nil when script not found" do
        retrieved = ScriptStatusModel.get(name: 'nonexistent', scope: 'DEFAULT')
        expect(retrieved).to be_nil
      end
    end

    describe "self.names" do
      it "returns running script names" do
        model1 = generate_script_status(name: 'script1')
        model1.create()
        model2 = generate_script_status(name: 'script2')
        model2.create()
        names = ScriptStatusModel.names(scope: 'DEFAULT', type: 'running')
        expect(names).to include('script1')
        expect(names).to include('script2')
      end

      it "returns completed script names" do
        model = generate_script_status(name: 'script3', state: 'completed')
        model.create()
        names = ScriptStatusModel.names(scope: 'DEFAULT', type: 'completed')
        expect(names).to include('script3')
      end

      it "returns empty array when no scripts" do
        names = ScriptStatusModel.names(scope: 'DEFAULT', type: 'running')
        expect(names).to eq([])
      end
    end

    describe "self.all" do
      it "returns all running scripts" do
        model1 = generate_script_status(name: '1')
        model1.create()
        model2 = generate_script_status(name: '2')
        model2.create()
        all = ScriptStatusModel.all(scope: 'DEFAULT', type: 'running')
        expect(all.length).to eq(2)
        expect(all[0]).not_to be_nil
        expect(all[1]).not_to be_nil
      end

      it "returns all completed scripts" do
        model1 = generate_script_status(name: '1', state: 'completed')
        model1.create()
        model2 = generate_script_status(name: '2', state: 'stopped')
        model2.create()
        all = ScriptStatusModel.all(scope: 'DEFAULT', type: 'completed')
        expect(all.length).to eq(2)
      end

      it "respects offset and limit for running scripts" do
        5.times do |i|
          model = generate_script_status(name: i.to_s)
          model.create()
        end
        all = ScriptStatusModel.all(scope: 'DEFAULT', offset: 1, limit: 2, type: 'running')
        expect(all.length).to eq(2)
      end

      it "respects offset and limit for completed scripts" do
        5.times do |i|
          model = generate_script_status(name: i.to_s, state: 'completed')
          model.create()
        end
        all = ScriptStatusModel.all(scope: 'DEFAULT', offset: 1, limit: 2, type: 'completed')
        expect(all.length).to eq(2)
      end

      it "returns empty array when no scripts" do
        all = ScriptStatusModel.all(scope: 'DEFAULT', type: 'running')
        expect(all).to eq([])
      end
    end

    describe "self.count" do
      it "counts running scripts" do
        3.times do |i|
          model = generate_script_status(name: i.to_s)
          model.create()
        end
        count = ScriptStatusModel.count(scope: 'DEFAULT', type: 'running')
        expect(count).to eq(3)
      end

      it "counts completed scripts" do
        2.times do |i|
          model = generate_script_status(name: i.to_s, state: 'completed')
          model.create()
        end
        count = ScriptStatusModel.count(scope: 'DEFAULT', type: 'completed')
        expect(count).to eq(2)
      end

      it "returns 0 when no scripts" do
        count = ScriptStatusModel.count(scope: 'DEFAULT', type: 'running')
        expect(count).to eq(0)
      end
    end

    describe "create" do
      it "creates a running script in redis" do
        model = generate_script_status(name: 'script1')
        model.create()
        retrieved = ScriptStatusModel.get(name: 'script1', scope: 'DEFAULT', type: 'running')
        expect(retrieved).not_to be_nil
      end

      it "creates a completed script in redis" do
        model = generate_script_status(name: 'script2', state: 'completed')
        model.create()
        retrieved = ScriptStatusModel.get(name: 'script2', scope: 'DEFAULT', type: 'completed')
        expect(retrieved).not_to be_nil
      end

      it "sets updated_at timestamp" do
        model = generate_script_status(name: 'script3')
        model.create()
        expect(model.updated_at).not_to be_nil
      end

      it "adds to ordered set on create" do
        model = generate_script_status(name: 'script4')
        model.create()
        names = ScriptStatusModel.names(scope: 'DEFAULT', type: 'running')
        expect(names).to include('script4')
      end

      it "does not add to ordered set on update" do
        model = generate_script_status(name: 'script5')
        model.create()
        initial_count = ScriptStatusModel.count(scope: 'DEFAULT', type: 'running')
        model.create(update: true)
        final_count = ScriptStatusModel.count(scope: 'DEFAULT', type: 'running')
        expect(initial_count).to eq(final_count)
      end
    end

    describe "update" do
      it "updates a running script" do
        model = generate_script_status(name: 'script1')
        model.create()
        model.line_no = 50
        model.update()
        retrieved = ScriptStatusModel.get(name: 'script1', scope: 'DEFAULT', type: 'running')
        expect(retrieved['line_no']).to eq(50)
      end

      it "moves script from running to completed" do
        model = generate_script_status(name: 'script2')
        model.create()
        expect(ScriptStatusModel.get(name: 'script2', scope: 'DEFAULT', type: 'running')).not_to be_nil

        model.instance_variable_set(:@state, 'completed')
        model.update()

        # After transitioning to completed, the script should no longer be in running
        # We need to force the type check to only look at running, not auto
        running_result = ScriptStatusModel.store.hget("#{ScriptStatusModel::RUNNING_PRIMARY_KEY}__DEFAULT", 'script2')
        expect(running_result).to be_nil
        expect(ScriptStatusModel.get(name: 'script2', scope: 'DEFAULT', type: 'completed')).not_to be_nil
      end

      it "removes from running when transitioning to stopped" do
        model = generate_script_status(name: 'script3')
        model.create()
        model.instance_variable_set(:@state, 'stopped')
        model.update()

        running_result = ScriptStatusModel.store.hget("#{ScriptStatusModel::RUNNING_PRIMARY_KEY}__DEFAULT", 'script3')
        expect(running_result).to be_nil
        expect(ScriptStatusModel.get(name: 'script3', scope: 'DEFAULT', type: 'completed')).not_to be_nil
      end

      it "removes from running when transitioning to crashed" do
        model = generate_script_status(name: 'script4')
        model.create()
        model.instance_variable_set(:@state, 'crashed')
        model.update()

        running_result = ScriptStatusModel.store.hget("#{ScriptStatusModel::RUNNING_PRIMARY_KEY}__DEFAULT", 'script4')
        expect(running_result).to be_nil
        expect(ScriptStatusModel.get(name: 'script4', scope: 'DEFAULT', type: 'completed')).not_to be_nil
      end

      it "removes from running when transitioning to killed" do
        model = generate_script_status(name: 'script5')
        model.create()
        model.instance_variable_set(:@state, 'killed')
        model.update()

        running_result = ScriptStatusModel.store.hget("#{ScriptStatusModel::RUNNING_PRIMARY_KEY}__DEFAULT", 'script5')
        expect(running_result).to be_nil
        expect(ScriptStatusModel.get(name: 'script5', scope: 'DEFAULT', type: 'completed')).not_to be_nil
      end
    end

    describe "destroy" do
      it "removes a running script from redis" do
        model = generate_script_status(name: 'script1')
        model.create()
        model.destroy()
        retrieved = ScriptStatusModel.get(name: 'script1', scope: 'DEFAULT', type: 'running')
        expect(retrieved).to be_nil
      end

      it "removes a completed script from redis" do
        model = generate_script_status(name: 'script2', state: 'completed')
        model.create()
        model.destroy()
        retrieved = ScriptStatusModel.get(name: 'script2', scope: 'DEFAULT', type: 'completed')
        expect(retrieved).to be_nil
      end

      it "removes from ordered set" do
        model = generate_script_status(name: 'script3')
        model.create()
        model.destroy()
        names = ScriptStatusModel.names(scope: 'DEFAULT', type: 'running')
        expect(names).not_to include('script3')
      end
    end

    describe "as_json" do
      it "includes all attributes" do
        model = generate_script_status(
          name: 'script1',
          state: 'running',
          shard: 1,
          filename: 'test.rb',
          current_filename: 'current.rb',
          line_no: 42,
          start_line_no: 1,
          end_line_no: 100,
          username: 'testuser',
          user_full_name: 'Test User',
          start_time: '2025-01-01T00:00:00Z',
          end_time: '2025-01-01T01:00:00Z',
          disconnect: true,
          environment: { 'VAR' => 'value' },
          suite_runner: 'suite1',
          errors: ['error1'],
          pid: 12345,
          log: '/log',
          report: '/report',
          script_engine: 'ruby'
        )
        model.create()
        json = model.as_json()

        expect(json['name']).to eq('script1')
        expect(json['state']).to eq('running')
        expect(json['shard']).to eq(1)
        expect(json['filename']).to eq('test.rb')
        expect(json['current_filename']).to eq('current.rb')
        expect(json['line_no']).to eq(42)
        expect(json['start_line_no']).to eq(1)
        expect(json['end_line_no']).to eq(100)
        expect(json['username']).to eq('testuser')
        expect(json['user_full_name']).to eq('Test User')
        expect(json['start_time']).to eq('2025-01-01T00:00:00Z')
        expect(json['end_time']).to eq('2025-01-01T01:00:00Z')
        expect(json['disconnect']).to be true
        expect(json['environment']).to eq({ 'VAR' => 'value' })
        expect(json['suite_runner']).to eq('suite1')
        expect(json['errors']).to eq(['error1'])
        expect(json['pid']).to eq(12345)
        expect(json['log']).to eq('/log')
        expect(json['report']).to eq('/report')
        expect(json['script_engine']).to eq('ruby')
        expect(json['updated_at']).not_to be_nil
        expect(json['scope']).to eq('DEFAULT')
      end
    end

    describe "multiple scopes" do
      it "isolates scripts by scope" do
        model1 = generate_script_status(name: 'script1', scope: 'SCOPE1')
        model1.create()
        model2 = generate_script_status(name: 'script2', scope: 'SCOPE2')
        model2.create()

        scope1_names = ScriptStatusModel.names(scope: 'SCOPE1', type: 'running')
        scope2_names = ScriptStatusModel.names(scope: 'SCOPE2', type: 'running')

        expect(scope1_names).to include('script1')
        expect(scope1_names).not_to include('script2')
        expect(scope2_names).to include('script2')
        expect(scope2_names).not_to include('script1')
      end
    end
  end
end
