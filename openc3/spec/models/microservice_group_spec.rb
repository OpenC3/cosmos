# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
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
require 'tempfile'
require 'openc3/models/target_model'
require 'openc3/models/microservice_group'
require 'openc3/models/microservice_model'

module OpenC3
  describe MicroserviceGroup do
    let(:scope) { 'DEFAULT' }
    let(:multi) { "#{scope}__MULTIGROUP__HK" }
    let(:pymulti) { "#{scope}__PYMULTIGROUP__HK" }

    before(:each) do
      mock_redis()
      local_s3()
      @bucket = Bucket.getClient.create("config")
      allow(Logger).to receive(:info)
    end

    after(:each) do
      Bucket.getClient.delete(@bucket) if @bucket
      local_s3_unset()
    end

    def add_target(target_name, group: 'HK', language: 'ruby', plugin: 'PLUGIN', db_shard: 0, shard: 0)
      TargetModel.new(name: target_name, folder_name: target_name, microservice_group: group, language: language,
                      plugin: plugin, db_shard: db_shard, shard: shard, scope: scope).create
    end

    def add_child(name, parent, cmd: ['ruby', 'decom_microservice.rb'], **kwargs)
      MicroserviceModel.new(name: "#{scope}__#{name}", parent: parent, cmd: cmd, scope: scope, **kwargs).create
    end

    def model(name)
      MicroserviceModel.get_model(name: name, scope: scope)
    end

    describe "TargetModel handle_config" do
      def parse(text)
        model = TargetModel.new(folder_name: "TEST", name: "TEST", scope: scope)
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts text
        tf.close
        parser.parse_file(tf.path) { |keyword, params| model.handle_config(parser, keyword, params) }
        tf.unlink
        model
      end

      it "parses MICROSERVICE_GROUP" do
        expect(parse("MICROSERVICE_GROUP housekeeping").as_json['microservice_group']).to eql 'HOUSEKEEPING'
      end

      it "rejects group names with a double underscore" do
        expect { parse("MICROSERVICE_GROUP BAD__NAME") }.to raise_error(ConfigParser::Error, /double underscore/)
      end
    end

    describe "validate_member" do
      def target(name, **kwargs)
        TargetModel.new(name: name, folder_name: name, microservice_group: 'HK', plugin: 'PLUGIN', scope: scope, **kwargs)
      end

      it "accepts a compatible target" do
        add_target('A')
        expect { MicroserviceGroup.validate_member(target('B', language: 'ruby')) }.to_not raise_error
      end

      it "rejects TARGET_MICROSERVICE" do
        expect { MicroserviceGroup.validate_member(target('B', target_microservices: { 'DECOM' => [[]] })) }.to \
          raise_error(/cannot use both MICROSERVICE_GROUP and TARGET_MICROSERVICE/)
      end

      it "rejects a different db_shard or shard" do
        add_target('A', db_shard: 1)
        expect { MicroserviceGroup.validate_member(target('B', db_shard: 0)) }.to raise_error(/DB_SHARD 0 but microservice group HK uses DB_SHARD 1/)
        expect { MicroserviceGroup.validate_member(target('B', db_shard: 1, shard: 3)) }.to raise_error(/SHARD 3 but microservice group HK uses SHARD 0/)
      end

      it "rejects Python decom targets from different plugins" do
        add_target('A', language: 'python', plugin: 'PLUGIN1')
        expect { MicroserviceGroup.validate_member(target('B', language: 'python', plugin: 'PLUGIN2')) }.to raise_error(/another plugin/)
        expect { MicroserviceGroup.validate_member(target('B', language: 'python', plugin: 'PLUGIN1')) }.to_not raise_error
        expect { MicroserviceGroup.validate_member(target('B', language: 'ruby', plugin: 'PLUGIN2')) }.to_not raise_error
      end

      it "ignores the target's own existing model and other groups" do
        add_target('B', db_shard: 1)
        add_target('C', group: 'OTHER', db_shard: 1)
        expect { MicroserviceGroup.validate_member(target('B', db_shard: 0)) }.to_not raise_error
      end
    end

    describe "update" do
      it "creates the parents that have children" do
        add_child('DECOM__A', multi, needs_dependencies: true, shard: 2, db_shard: 1)
        add_child('PACKETLOG__A', multi, cmd: ['ruby', 'log_microservice.rb'], shard: 2, db_shard: 1)
        MicroserviceGroup.update('HK', scope: scope)

        ruby = model(multi)
        expect(ruby.cmd).to eql ['ruby', 'multi_microservice.rb']
        expect(ruby.work_dir).to eql '/openc3/lib/openc3/microservices'
        expect(ruby.parent).to be_nil
        expect(ruby.plugin).to be_nil
        expect(ruby.needs_dependencies).to be true
        expect(ruby.shard).to eql 2
        expect(ruby.db_shard).to eql 1
        # No Python children so no Python parent
        expect(model(pymulti)).to be_nil
      end

      it "gives the Python parent the plugin of its Python decom children" do
        add_child('TSDB__A', pymulti, cmd: ['python', 'tsdb_microservice.py'], plugin: 'OTHER')
        MicroserviceGroup.update('HK', scope: scope)
        expect(model(pymulti).cmd[1]).to eql 'multi_microservice.py'
        expect(model(pymulti).work_dir).to eql '/openc3/python/openc3/microservices'
        expect(model(pymulti).plugin).to be_nil

        add_child('DECOM__B', pymulti, cmd: ['python', 'decom_microservice.py'], plugin: 'PYPLUGIN')
        MicroserviceGroup.update('HK', scope: scope)
        expect(model(pymulti).plugin).to eql 'PYPLUGIN'
      end

      it "removes parents without children" do
        add_child('DECOM__A', multi)
        add_child('TSDB__A', pymulti, cmd: ['python', 'tsdb_microservice.py'])
        MicroserviceGroup.update('HK', scope: scope)
        model("#{scope}__TSDB__A").destroy
        MicroserviceGroup.update('HK', scope: scope)
        expect(model(multi)).to_not be_nil
        expect(model(pymulti)).to be_nil
        model("#{scope}__DECOM__A").destroy
        MicroserviceGroup.update('HK', scope: scope)
        expect(model(multi)).to be_nil
      end

      it "doesn't rewrite unchanged parents" do
        add_child('DECOM__A', multi)
        MicroserviceGroup.update('HK', scope: scope)
        updated_at = MicroserviceModel.get(name: multi, scope: scope)['updated_at']
        # Another child doesn't change the parent, the operator restarts it
        add_child('DECOM__B', multi)
        expect_any_instance_of(MicroserviceModel).to_not receive(:update)
        expect_any_instance_of(MicroserviceModel).to_not receive(:create)
        MicroserviceGroup.update('HK', scope: scope)
        expect(MicroserviceModel.get(name: multi, scope: scope)['updated_at']).to eql updated_at
      end

      it "only uses children of its own group" do
        add_child('DECOM__A', "#{scope}__MULTIGROUP__OTHER")
        add_child('DECOM__B', "#{scope}__MULTI__B")
        MicroserviceGroup.update('HK', scope: scope)
        expect(model(multi)).to be_nil
      end

      it "times out if the group lock is held" do
        stub_const("OpenC3::MicroserviceGroup::LOCK_TIMEOUT_SECONDS", 0.2)
        Store.set("#{scope}__microservice_group_lock__HK", 'other', nx: true, ex: 10)
        expect { MicroserviceGroup.update('HK', scope: scope) }.to raise_error(/Timeout waiting for microservice group HK lock/)
        # Didn't release another holder's lock
        expect(Store.get("#{scope}__microservice_group_lock__HK")).to eql 'other'
      end

      it "releases the lock after an error" do
        allow(MicroserviceModel).to receive(:all).and_raise("boom")
        expect { MicroserviceGroup.update('HK', scope: scope) }.to raise_error("boom")
        expect(Store.get("#{scope}__microservice_group_lock__HK")).to be_nil
      end
    end

    describe "TargetModel deploy and undeploy" do
      let(:target_dir) { File.join(SPEC_DIR, "install", "config") }

      before(:each) do
        allow(ENV).to receive(:[]).and_call_original
        %w(OPENC3_TSDB_HOSTNAME OPENC3_TSDB_QUERY_PORT OPENC3_TSDB_INGEST_PORT OPENC3_TSDB_USERNAME OPENC3_TSDB_PASSWORD).each do |env|
          allow(ENV).to receive(:[]).with(env).and_return('x')
        end
      end

      def deploy(name, **kwargs)
        model = TargetModel.new(folder_name: 'INST', name: name, microservice_group: 'HK', plugin: 'PLUGIN', scope: scope,
                                tlm_log_retain_time: 60, **kwargs)
        model.create
        capture_io { model.deploy(target_dir, {}) }
        model
      end

      it "runs each member's own microservices in the group's MULTI microservices" do
        deploy('INST')
        deploy('INST2')
        expect(TargetModel.get(name: 'INST', scope: scope)['language']).to eql 'ruby'
        %w(INST INST2).each do |target|
          %w(DECOM COMMANDLOG PACKETLOG CLEANUP).each do |type|
            expect(model("#{scope}__#{type}__#{target}").parent).to eql multi
          end
          # TSDB is Python
          expect(model("#{scope}__TSDB__#{target}").parent).to eql pymulti
          # Each target keeps its own settings
          expect(model("#{scope}__PACKETLOG__#{target}").options).to include(["CYCLE_TIME", 600])
          # No MULTI of its own
          expect(model("#{scope}__MULTI__#{target}")).to be_nil
        end
        expect(model(multi).cmd).to eql ['ruby', 'multi_microservice.rb']
        expect(model(pymulti).cmd[1]).to eql 'multi_microservice.py'

        TargetModel.get_model(name: 'INST', scope: scope).destroy
        expect(model("#{scope}__DECOM__INST")).to be_nil
        expect(model("#{scope}__TSDB__INST")).to be_nil
        expect(model(multi)).to_not be_nil
        expect(model(pymulti)).to_not be_nil
        TargetModel.get_model(name: 'INST2', scope: scope).destroy
        expect(model(multi)).to be_nil
        expect(model(pymulti)).to be_nil
      end

      it "fails before writing anything if the target can't join the group" do
        deploy('INST', db_shard: 0)
        model = TargetModel.new(folder_name: 'INST', name: 'INST2', microservice_group: 'HK', plugin: 'PLUGIN', db_shard: 1, scope: scope)
        model.create
        expect { capture_io { model.deploy(target_dir, {}) } }.to raise_error(/DB_SHARD 1 but microservice group HK uses DB_SHARD 0/)
        expect(Store.instance(db_shard: 1).hkeys("#{scope}__openc3tlm__INST2")).to be_empty
        expect(model("#{scope}__DECOM__INST2")).to be_nil
      end

      it "doesn't change targets without a group" do
        model = TargetModel.new(folder_name: 'INST', name: 'INST', plugin: 'PLUGIN', scope: scope)
        model.create
        capture_io { model.deploy(target_dir, {}) }
        expect(model("#{scope}__DECOM__INST").parent).to eql "#{scope}__MULTI__INST"
        expect(model("#{scope}__TSDB__INST").parent).to be_nil
        expect(model("#{scope}__MULTI__INST")).to_not be_nil
      end
    end
  end
end
