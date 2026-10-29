require 'spec_helper'
require 'openc3/models/scope_model'
require 'openc3/models/microservice_model'
require 'openc3/models/bridge_model'

# Loading a migration normally runs it immediately. Load the class without
# modifying any test-store records before the examples start.
previous_no_migrate = ENV['OPENC3_NO_MIGRATE']
ENV['OPENC3_NO_MIGRATE'] = 'true'
begin
  require 'openc3/migrations/20260704000000_default_bridge'
ensure
  if previous_no_migrate.nil?
    ENV.delete('OPENC3_NO_MIGRATE')
  else
    ENV['OPENC3_NO_MIGRATE'] = previous_no_migrate
  end
end

module OpenC3
  describe DefaultBridge do
    let(:service) { instance_double(MicroserviceModel) }

    before(:each) do
      allow(ScopeModel).to receive(:get_all_models).with(scope: nil)
        .and_return({ 'DEFAULT' => double(shard: 2) })
      allow(BridgeModel).to receive(:build_microservice)
        .with(bridge_name: 'DEFAULT', scope: 'DEFAULT', shard: 2)
        .and_return(service)
      allow(Logger).to receive(:info)
    end

    it 'creates a missing bridge without calling plugin deployment' do
      allow(MicroserviceModel).to receive(:get_model).and_return(nil)
      expect(service).to receive(:create).once
      expect(service).not_to receive(:deploy)

      DefaultBridge.run
    end

    it 'skips a bridge that already exists on the next run' do
      allow(MicroserviceModel).to receive(:get_model)
        .and_return(nil, { 'name' => 'DEFAULT__BRIDGE__DEFAULT' })
      expect(service).to receive(:create).once

      2.times { DefaultBridge.run }
    end
  end
end
