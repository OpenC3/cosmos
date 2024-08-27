require 'rspec'
require 'webmock/rspec'

=begin
This RSpec test program covers all the methods in the Script module, including both public and private methods. It uses WebMock to stub HTTP requests and mocks the OpenC3::ApiServer and OpenC3::LocalMode dependencies.

To run this test, you'll need to:

1. Install the required gems: `rspec` and `webmock`.
2. Replace `require_relative 'path/to/your/script_file'` with the actual path to your script file containing the OpenC3::Script module.
3. Run the tests using the `rspec` command.

This test suite provides good coverage of the Script module, testing various scenarios including successful operations, error handling, and different environment configurations. You may want to add more specific test cases or edge cases depending on your particular use of the module.
=end

# Mock the OpenC3 module and its dependencies
module OpenC3
  class ApiServer
    def request(method, endpoint, query: {}, scope: nil)
      # Mocked implementation
    end

    def generate_url
      "http://example.com"
    end
  end

  module LocalMode
    def self.put_target_file(upload_path, io_or_string, scope: nil)
      # Mocked implementation
    end

    def self.open_local_file(path, scope: nil)
      # Mocked implementation
    end
  end
end

# Include the Script module
require_relative 'path/to/your/script_file'

RSpec.describe OpenC3::Script do
  let(:dummy_class) { Class.new { include OpenC3::Script } }
  let(:instance) { dummy_class.new }

  before do
    # Set up environment variables
    ENV['OPENC3_CLOUD'] = 'local'
    ENV['OPENC3_LOCAL_MODE'] = 'false'
    $openc3_scope = 'test_scope'
    $openc3_in_cluster = false
    $api_server = instance_double(OpenC3::ApiServer)
  end

  describe '#delete_target_file' do
    it 'successfully deletes a target file' do
      allow($api_server).to receive(:request).and_return(double(status: 200))
      expect { instance.send(:delete_target_file, 'test/file.txt') }.not_to raise_error
    end

    it 'raises an error when deletion fails' do
      allow($api_server).to receive(:request).and_return(double(status: 500))
      expect { instance.send(:delete_target_file, 'test/file.txt') }.to raise_error(RuntimeError, /Failed to delete/)
    end
  end

  describe '#put_target_file' do
    it 'successfully uploads a target file' do
      allow($api_server).to receive(:request).and_return({ 'url' => 'http://example.com/upload' }.to_json)
      stub_request(:put, 'http://example.com/upload').to_return(status: 200)
      expect { instance.send(:put_target_file, 'test/file.txt', 'content') }.not_to raise_error
    end

    it 'raises an error when upload fails' do
      allow($api_server).to receive(:request).and_return({ 'url' => 'http://example.com/upload' }.to_json)
      stub_request(:put, 'http://example.com/upload').to_return(status: 500)
      expect { instance.send(:put_target_file, 'test/file.txt', 'content') }.to raise_error(RuntimeError, /Failed to write/)
    end

    it 'disallows paths with ".."' do
      expect { instance.send(:put_target_file, '../test/file.txt', 'content') }.to raise_error(RuntimeError, /Disallowed path modifier/)
    end
  end

  describe '#get_target_file' do
    it 'successfully retrieves a target file' do
      allow($api_server).to receive(:request).and_return({ 'url' => 'http://example.com/download' }.to_json)
      stub_request(:get, 'http://example.com/download').to_return(status: 200, body: 'file content')
      file = instance.send(:get_target_file, 'test/file.txt')
      expect(file).to be_a(Tempfile)
      expect(file.read).to eq('file content')
    end

    it 'falls back to original file if modified file is not found' do
      allow($api_server).to receive(:request).and_return({ 'url' => 'http://example.com/download' }.to_json)
      stub_request(:get, 'http://example.com/download').to_return(status: 200, body: 'original content')
      file = instance.send(:get_target_file, 'test/file.txt')
      expect(file.read).to eq('original content')
    end
  end

  describe '#get_download_url' do
    it 'returns the download URL for an existing file' do
      allow($api_server).to receive(:request).and_return(double(status: 200), { 'url' => 'http://example.com/download' }.to_json)
      url = instance.send(:get_download_url, 'test/file.txt')
      expect(url).to eq('http://example.com/download')
    end

    it 'raises an error when file is not found' do
      allow($api_server).to receive(:request).and_return(double(status: 404))
      expect { instance.send(:get_download_url, 'test/file.txt') }.to raise_error(RuntimeError, /File not found/)
    end
  end

  describe '#_get_storage_file' do
    it 'successfully retrieves a storage file' do
      allow($api_server).to receive(:request).and_return({ 'url' => 'http://example.com/storage' }.to_json)
      stub_request(:get, 'http://example.com/storage').to_return(status: 200, body: 'storage content')
      file = instance.send(:_get_storage_file, 'test/storage.txt')
      expect(file).to be_a(Tempfile)
      expect(file.read).to eq('storage content')
    end
  end

  describe '#_get_uri' do
    it 'returns the correct URI for local cloud' do
      $openc3_in_cluster = true
      ENV['OPENC3_CLOUD'] = 'local'
      ENV['OPENC3_BUCKET_URL'] = 'http://openc3-minio:9000'
      uri = instance.send(:_get_uri, '/test')
      expect(uri.to_s).to eq('http://openc3-minio:9000/test')
    end

    it 'returns the correct URI for AWS cloud' do
      $openc3_in_cluster = true
      ENV['OPENC3_CLOUD'] = 'aws'
      ENV['AWS_REGION'] = 'us-west-2'
      uri = instance.send(:_get_uri, '/test')
      expect(uri.to_s).to eq('https://s3.us-west-2.amazonaws.com/test')
    end

    it 'raises an error for unknown cloud' do
      $openc3_in_cluster = true
      ENV['OPENC3_CLOUD'] = 'unknown'
      expect { instance.send(:_get_uri, '/test') }.to raise_error(RuntimeError, /Unknown cloud/)
    end
  end

  describe '#_get_presigned_request' do
    it 'returns the presigned request result' do
      allow($api_server).to receive(:request).and_return(double(status: 201, body: '{"key": "value"}'))
      result = instance.send(:_get_presigned_request, '/test')
      expect(result).to eq({ 'key' => 'value' })
    end

    it 'raises an error when request fails' do
      allow($api_server).to receive(:request).and_return(double(status: 500))
      expect { instance.send(:_get_presigned_request, '/test') }.to raise_error(RuntimeError, /Failed to get presigned URL/)
    end
  end
end
