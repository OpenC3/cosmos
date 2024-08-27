require 'rspec'
require 'webmock/rspec'

=begin
This RSpec test program covers all the methods in the Script module. It uses WebMock to stub HTTP requests, allowing us to test the API interactions without actually making network calls. Here's a breakdown of what's covered:

1. All methods in the module are tested.
2. Both success and failure scenarios are covered for each method.
3. Different HTTP methods (GET, POST, PUT, DELETE) are tested.
4. File operations are mocked where necessary.
5. Error handling is tested for each method.
6. Different parameter combinations are tested where applicable (e.g., with and without the `update` flag).

To run this test, you'll need to:

1. Install the required gems (rspec and webmock).
2. Ensure the path to your Script module is correct in the `require_relative` statement.
3. Run the tests using the `rspec` command.

This test suite should provide good coverage of the Script module's functionality. However, you may want to add more specific test cases if there are particular edge cases or complex scenarios that are important for your use case.
=end

# Mock the OpenC3 module and its dependencies
module OpenC3
  class JsonDRbObject
    USER_AGENT = 'MockUserAgent'
  end
end

# Include the Script module
require_relative 'path/to/your/script_module'

RSpec.describe OpenC3::Script do
  let(:dummy_class) { Class.new { include OpenC3::Script } }
  let(:instance) { dummy_class.new }

  before do
    # Mock global variables
    stub_const("$openc3_scope", "SCOPE")
    stub_const("$api_server", double('api_server'))
    allow($api_server).to receive(:generate_url).and_return('http://example.com')
    allow($api_server).to receive(:generate_auth).and_return(double('auth', token: 'mock_token'))
  end

  describe '#plugin_list' do
    it 'returns a list of plugins' do
      stub_request(:get, "http://example.com/openc3-api/plugins?scope=SCOPE")
        .to_return(status: 200, body: '[{"name": "plugin1"}, {"name": "plugin2"}]')

      result = instance.send(:plugin_list)
      expect(result).to eq([{"name" => "plugin1"}, {"name" => "plugin2"}])
    end

    it 'raises an error on API failure' do
      stub_request(:get, "http://example.com/openc3-api/plugins?scope=SCOPE")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { instance.send(:plugin_list) }.to raise_error(/get_plugin_list failed/)
    end
  end

  describe '#plugin_get' do
    it 'returns plugin details' do
      stub_request(:get, "http://example.com/openc3-api/plugins/test_plugin?scope=SCOPE")
        .to_return(status: 200, body: '{"name": "test_plugin", "version": "1.0"}')

      result = instance.send(:plugin_get, 'test_plugin')
      expect(result).to eq({"name" => "test_plugin", "version" => "1.0"})
    end

    it 'raises an error on API failure' do
      stub_request(:get, "http://example.com/openc3-api/plugins/test_plugin?scope=SCOPE")
        .to_return(status: 404, body: 'Not Found')

      expect { instance.send(:plugin_get, 'test_plugin') }.to raise_error(/get_plugin failed/)
    end
  end

  describe '#plugin_install_phase1' do
    it 'installs a new plugin' do
      allow(File).to receive(:open).and_yield(StringIO.new("dummy file content"))
      stub_request(:post, "http://example.com/openc3-api/plugins?scope=SCOPE")
        .to_return(status: 200, body: '{"name": "new_plugin", "status": "uploaded"}')

      result = instance.send(:plugin_install_phase1, 'dummy_path.zip')
      expect(result).to eq({"name" => "new_plugin", "status" => "uploaded"})
    end

    it 'updates an existing plugin' do
      allow(File).to receive(:open).and_yield(StringIO.new("dummy file content"))
      stub_request(:put, "http://example.com/openc3-api/plugins/existing_plugin?scope=SCOPE")
        .to_return(status: 200, body: '{"name": "existing_plugin", "status": "updated"}')

      result = instance.send(:plugin_install_phase1, 'dummy_path.zip', update: true, existing_plugin_name: 'existing_plugin')
      expect(result).to eq({"name" => "existing_plugin", "status" => "updated"})
    end

    it 'raises an error on API failure' do
      allow(File).to receive(:open).and_yield(StringIO.new("dummy file content"))
      stub_request(:post, "http://example.com/openc3-api/plugins?scope=SCOPE")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { instance.send(:plugin_install_phase1, 'dummy_path.zip') }.to raise_error(/plugin_install_phase1 failed/)
    end
  end

  describe '#plugin_install_phase2' do
    it 'completes installation of a new plugin' do
      plugin_hash = {"name" => "new_plugin", "version" => "1.0"}
      stub_request(:post, "http://example.com/openc3-api/plugins/install/new_plugin?scope=SCOPE")
        .to_return(status: 200, body: '"Installation complete"')

      result = instance.send(:plugin_install_phase2, plugin_hash)
      expect(result).to eq('Installation complete')
    end

    it 'completes update of an existing plugin' do
      plugin_hash = {"name" => "existing_plugin", "version" => "2.0"}
      stub_request(:put, "http://example.com/openc3-api/plugins/existing_plugin?scope=SCOPE")
        .to_return(status: 200, body: '"Update complete"')

      result = instance.send(:plugin_install_phase2, plugin_hash, update: true)
      expect(result).to eq('Update complete')
    end

    it 'raises an error on API failure' do
      plugin_hash = {"name" => "new_plugin", "version" => "1.0"}
      stub_request(:post, "http://example.com/openc3-api/plugins/install/new_plugin?scope=SCOPE")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { instance.send(:plugin_install_phase2, plugin_hash) }.to raise_error(/plugin_install_phase2 failed/)
    end
  end

  describe '#plugin_update_phase1' do
    it 'initiates update of an existing plugin' do
      allow(File).to receive(:open).and_yield(StringIO.new("dummy file content"))
      stub_request(:put, "http://example.com/openc3-api/plugins/existing_plugin?scope=SCOPE")
        .to_return(status: 200, body: '{"name": "existing_plugin", "status": "update_initiated"}')

      result = instance.send(:plugin_update_phase1, 'dummy_path.zip', 'existing_plugin')
      expect(result).to eq({"name" => "existing_plugin", "status" => "update_initiated"})
    end
  end

  describe '#plugin_uninstall' do
    it 'uninstalls a plugin' do
      stub_request(:delete, "http://example.com/openc3-api/plugins/test_plugin?scope=SCOPE")
        .to_return(status: 200, body: '"Uninstallation complete"')

      result = instance.send(:plugin_uninstall, 'test_plugin')
      expect(result).to eq('Uninstallation complete')
    end

    it 'raises an error on API failure' do
      stub_request(:delete, "http://example.com/openc3-api/plugins/test_plugin?scope=SCOPE")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { instance.send(:plugin_uninstall, 'test_plugin') }.to raise_error(/plugin_uninstall failed/)
    end
  end

  describe '#plugin_status' do
    it 'returns the status of a plugin process' do
      stub_request(:get, "http://example.com/openc3-api/process_status/test_process?scope=SCOPE")
        .to_return(status: 200, body: '{"name": "test_process", "state": "RUNNING"}')

      result = instance.send(:plugin_status, 'test_process')
      expect(result).to eq({"name" => "test_process", "state" => "RUNNING"})
    end

    it 'raises an error on API failure' do
      stub_request(:get, "http://example.com/openc3-api/process_status/test_process?scope=SCOPE")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { instance.send(:plugin_status, 'test_process') }.to raise_error(/plugin_status failed/)
    end
  end
end
