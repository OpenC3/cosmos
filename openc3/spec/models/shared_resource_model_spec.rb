# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/shared_resource_model'

module OpenC3
  describe SharedResourceModel do
    before(:each) do
      mock_redis()
      allow(Logger).to receive(:info)
      allow(Logger).to receive(:warn)
      SharedResourceModel.clear_cache
    end

    def add_interface(scope, name: 'INT', shard: 0)
      SharedResourceModel.add_member('CHAMBER', scope: scope, type: 'INTERFACE', member_name: "#{scope}__INTERFACE__#{name}", shard: shard)
    end

    describe "self.validate_name" do
      it "upcases valid names" do
        expect(SharedResourceModel.validate_name('chamber_1')).to eql 'CHAMBER_1'
      end

      it "rejects invalid names" do
        expect { SharedResourceModel.validate_name('BAD NAME') }.to raise_error(/Invalid shared resource name/)
        expect { SharedResourceModel.validate_name('BAD__NAME') }.to raise_error(/Invalid shared resource name/)
        expect { SharedResourceModel.validate_name('') }.to raise_error(/Invalid shared resource name/)
      end
    end

    describe "self.add_member" do
      it "stores the global record on db_shard 0" do
        expect(Store).to receive(:instance).with(db_shard: 0).at_least(:once).and_call_original
        expect(Store).not_to receive(:instance).with(db_shard: 1)
        add_interface('DEFAULT', shard: 1)
        expect(Store.instance(db_shard: 0).hget('openc3_shared_resources', 'CHAMBER')).not_to be_nil
      end

      it "gives ownership to the first scope" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        record = SharedResourceModel.get('CHAMBER')
        expect(record['owner']).to eql 'DEFAULT'
        expect(record['state']).to eql 'ACTIVE'
        expect(record['members'].keys).to eql %w(DEFAULT OTHER)
        expect(record['members']['OTHER']).to eql [{ 'type' => 'INTERFACE', 'name' => 'OTHER__INTERFACE__INT', 'shard' => 0 }]
      end

      it "is idempotent and updates the shard" do
        add_interface('DEFAULT')
        add_interface('DEFAULT', shard: 2)
        members = SharedResourceModel.get('CHAMBER')['members']['DEFAULT']
        expect(members).to eql [{ 'type' => 'INTERFACE', 'name' => 'DEFAULT__INTERFACE__INT', 'shard' => 2 }]
      end

      it "allows several members per scope" do
        add_interface('DEFAULT')
        SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'TARGET', member_name: 'INST')
        members = SharedResourceModel.get('CHAMBER')['members']['DEFAULT']
        expect(members.length).to eql 2
        expect(members[1]).to eql({ 'type' => 'TARGET', 'name' => 'INST' })
      end

      it "rejects unknown member types" do
        expect { SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'TOOL', member_name: 'X') }.to raise_error(/Invalid shared resource member type/)
      end
    end

    describe "self.member?" do
      it "checks the scope, type, and name" do
        expect(SharedResourceModel.member?('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')).to be false
        add_interface('DEFAULT')
        expect(SharedResourceModel.member?('chamber', scope: 'DEFAULT', type: 'interface', member_name: 'DEFAULT__INTERFACE__INT')).to be true
        expect(SharedResourceModel.member?('CHAMBER', scope: 'OTHER', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')).to be false
        expect(SharedResourceModel.member?('CHAMBER', scope: 'DEFAULT', type: 'ROUTER', member_name: 'DEFAULT__INTERFACE__INT')).to be false
      end
    end

    describe "self.remove_member" do
      it "keeps ownership when the owner's members are removed" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.remove_member('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')
        record = SharedResourceModel.get('CHAMBER')
        expect(record['owner']).to eql 'DEFAULT'
        expect(record['members'].keys).to eql ['OTHER']
        # Reinstalling (plugin upgrade) keeps ownership
        add_interface('DEFAULT')
        expect(SharedResourceModel.get('CHAMBER')['owner']).to eql 'DEFAULT'
      end

      it "deletes the record when the last member is removed" do
        add_interface('DEFAULT')
        expect(SharedResourceModel.remove_member('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')).to be_nil
        expect(SharedResourceModel.get('CHAMBER')).to be_nil
      end

      it "returns nil for an unknown resource" do
        expect(SharedResourceModel.remove_member('NOPE', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'X')).to be_nil
      end
    end

    describe "self.switch" do
      it "raises if the resource doesn't exist" do
        expect { SharedResourceModel.switch('NOPE', to_scope: 'DEFAULT') }.to raise_error(/does not exist/)
      end

      it "raises if the scope has no members" do
        add_interface('DEFAULT')
        expect { SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER') }.to raise_error(/no members in scope 'OTHER'/)
      end

      it "does nothing if already active in the scope" do
        add_interface('DEFAULT')
        record = SharedResourceModel.switch('CHAMBER', to_scope: 'DEFAULT')
        expect(record['owner']).to eql 'DEFAULT'
        expect(record['state']).to eql 'ACTIVE'
      end

      it "switches immediately if the owner has no process members" do
        SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'TARGET', member_name: 'INST')
        SharedResourceModel.add_member('CHAMBER', scope: 'OTHER', type: 'TARGET', member_name: 'INST')
        record = SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        expect(record['owner']).to eql 'OTHER'
        expect(record['state']).to eql 'ACTIVE'
      end

      it "switches immediately if the owner has no members installed" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.remove_member('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')
        record = SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        expect(record['owner']).to eql 'OTHER'
        expect(record['state']).to eql 'ACTIVE'
      end

      it "hands off once every running member is acknowledged" do
        add_interface('DEFAULT', shard: 0)
        SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'MICROSERVICE', member_name: 'DEFAULT__USER__CTRL', shard: 1)
        SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'TARGET', member_name: 'INST')
        add_interface('OTHER')

        record = SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        expect(record['owner']).to eql 'DEFAULT'
        expect(record['state']).to eql 'RELEASING'
        expect(record['to']).to eql 'OTHER'
        expect(record['requested_at']).not_to be_nil
        # Targets have no process so aren't waited on
        expect(record['waiting']).to eql [{ 'name' => 'DEFAULT__INTERFACE__INT', 'shard' => 0 }, { 'name' => 'DEFAULT__USER__CTRL', 'shard' => 1 }]
        expect(SharedResourceModel.active?(record, 'DEFAULT')).to be false
        expect(SharedResourceModel.active?(record, 'OTHER')).to be false

        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect(record['state']).to eql 'RELEASING'
        expect(record['waiting']).to eql [{ 'name' => 'DEFAULT__USER__CTRL', 'shard' => 1 }]

        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__USER__CTRL'])
        expect(record['state']).to eql 'ACTIVE'
        expect(record['owner']).to eql 'OTHER'
        expect(record['to']).to be_nil
        expect(record['waiting']).to eql []
        expect(SharedResourceModel.active?(record, 'OTHER')).to be true
      end

      it "changes the destination while releasing" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        add_interface('THIRD')
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        record = SharedResourceModel.switch('CHAMBER', to_scope: 'THIRD')
        expect(record['state']).to eql 'RELEASING'
        expect(record['to']).to eql 'THIRD'
        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect(record['owner']).to eql 'THIRD'
      end

      it "forces the switch without waiting" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        expect(Logger).to receive(:warn).with(/forced/)
        record = SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER', force: true)
        expect(record['owner']).to eql 'OTHER'
        expect(record['state']).to eql 'ACTIVE'
      end

      it "keeps waiting on a member removed during the handoff" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        record = SharedResourceModel.remove_member('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')
        expect(record['state']).to eql 'RELEASING'
        expect(record['waiting'].length).to eql 1
        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect(record['owner']).to eql 'OTHER'
      end

      it "releases instead if the destination is removed during the handoff" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        record = SharedResourceModel.remove_member('CHAMBER', scope: 'OTHER', type: 'INTERFACE', member_name: 'OTHER__INTERFACE__INT')
        expect(record['to']).to be_nil
        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect(record['owner']).to be_nil
        expect(record['state']).to eql 'ACTIVE'
      end

      it "deletes the record if every member is removed during the handoff" do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        SharedResourceModel.remove_member('CHAMBER', scope: 'OTHER', type: 'INTERFACE', member_name: 'OTHER__INTERFACE__INT')
        record = SharedResourceModel.remove_member('CHAMBER', scope: 'DEFAULT', type: 'INTERFACE', member_name: 'DEFAULT__INTERFACE__INT')
        # Still waiting for the removed process to stop
        expect(record['waiting'].length).to eql 1
        expect(SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])).to be_nil
        expect(SharedResourceModel.get('CHAMBER')).to be_nil
      end
    end

    describe "self.release" do
      it "releases the resource from every scope" do
        add_interface('DEFAULT')
        record = SharedResourceModel.release('CHAMBER')
        expect(record['state']).to eql 'RELEASING'
        expect(record['to']).to be_nil
        record = SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect(record['owner']).to be_nil
        expect(record['state']).to eql 'ACTIVE'
        expect(SharedResourceModel.active?(record, 'DEFAULT')).to be false
        # Stays unowned when reinstalled
        add_interface('DEFAULT')
        expect(SharedResourceModel.get('CHAMBER')['owner']).to be_nil
        # Can be switched back
        expect(SharedResourceModel.switch('CHAMBER', to_scope: 'DEFAULT')['owner']).to eql 'DEFAULT'
      end

      it "raises if the resource doesn't exist" do
        expect { SharedResourceModel.release('NOPE') }.to raise_error(/does not exist/)
      end
    end

    describe "self.acknowledge" do
      it "returns nil when not releasing" do
        add_interface('DEFAULT')
        expect(SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])).to be_nil
        expect(SharedResourceModel.get('CHAMBER')['owner']).to eql 'DEFAULT'
      end
    end

    describe "checks" do
      before(:each) do
        add_interface('DEFAULT')
        add_interface('OTHER')
        SharedResourceModel.add_member('CHAMBER', scope: 'DEFAULT', type: 'TARGET', member_name: 'INST')
        SharedResourceModel.add_member('CHAMBER', scope: 'OTHER', type: 'TARGET', member_name: 'INST')
      end

      it "allows members of the active scope and non members" do
        SharedResourceModel.check_target_active('inst', scope: 'DEFAULT')
        SharedResourceModel.check_target_active('INST2', scope: 'OTHER')
        SharedResourceModel.check_interface_active('INTERFACE', 'int', scope: 'DEFAULT')
        SharedResourceModel.check_interface_active('ROUTER', 'INT', scope: 'OTHER')
      end

      it "rejects members of inactive scopes" do
        expect { SharedResourceModel.check_target_active('INST', scope: 'OTHER') }.to raise_error("Target INST is part of shared resource CHAMBER which is active in scope DEFAULT")
        expect { SharedResourceModel.check_interface_active('INTERFACE', 'INT', scope: 'OTHER') }.to raise_error("Interface INT is part of shared resource CHAMBER which is active in scope DEFAULT")
      end

      it "describes a switch in progress" do
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER')
        expect { SharedResourceModel.check_target_active('INST', scope: 'DEFAULT') }.to raise_error(/switching from scope DEFAULT to scope OTHER/)
        expect { SharedResourceModel.check_target_active('INST', scope: 'OTHER') }.to raise_error(/switching from scope DEFAULT to scope OTHER/)
        SharedResourceModel.release('CHAMBER')
        expect { SharedResourceModel.check_target_active('INST', scope: 'DEFAULT') }.to raise_error(/being released from scope DEFAULT/)
        SharedResourceModel.acknowledge('CHAMBER', ['DEFAULT__INTERFACE__INT'])
        expect { SharedResourceModel.check_target_active('INST', scope: 'DEFAULT') }.to raise_error(/not active in any scope/)
      end

      it "caches the records but clears the cache on changes" do
        SharedResourceModel.check_target_active('INST', scope: 'DEFAULT')
        # Changes made through the model clear the local cache immediately
        SharedResourceModel.switch('CHAMBER', to_scope: 'OTHER', force: true)
        SharedResourceModel.check_target_active('INST', scope: 'OTHER')
        # Changes from elsewhere are seen once the cache times out
        Store.instance(db_shard: 0).hdel('openc3_shared_resources', 'CHAMBER')
        SharedResourceModel.check_target_active('INST', scope: 'OTHER')
        expect(SharedResourceModel.find_by_member(scope: 'OTHER', type: 'TARGET', member_name: 'INST')).not_to be_nil
        expect(SharedResourceModel.find_by_member(scope: 'OTHER', type: 'TARGET', member_name: 'INST', cached: false)).to be_nil
      end
    end

    describe "lock" do
      it "times out if the lock is held" do
        Store.instance(db_shard: 0).set('openc3_shared_resources__lock', 'someone-else')
        stub_const('OpenC3::SharedResourceModel::LOCK_WAIT_SECONDS', 0.1)
        expect { add_interface('DEFAULT') }.to raise_error(/Timeout waiting for shared resource lock/)
        # Didn't release a lock it doesn't own
        expect(Store.instance(db_shard: 0).get('openc3_shared_resources__lock')).to eql 'someone-else'
      end
    end
  end
end
