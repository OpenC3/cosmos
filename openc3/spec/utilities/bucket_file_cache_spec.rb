require 'rspec'
require 'fileutils'
require 'tmpdir'

# Mock the OpenC3 module and its components
module OpenC3
  class Logger
    def self.debug(message); end
    def self.warn(message); end
    def self.error(message); end
  end

  class Bucket
    def self.getClient; MockBucketClient.new; end
  end
end

class MockBucketClient
  def get_object(bucket:, key:, path:)
    FileUtils.touch(path)
    OpenStruct.new
  end
end

# Include the BucketFileCache class definition here
# ... (paste the BucketFileCache class code here) ...

RSpec.describe BucketFileCache do
  let(:cache) { BucketFileCache.instance }

  before do
    # Reset the singleton instance before each test
    BucketFileCache.class_variable_set(:@@instance, nil)
    ENV['OPENC3_BUCKET_FILE_CACHE_SIZE'] = '1000000' # 1 MB for testing
  end

  describe '.instance' do
    it 'returns a singleton instance' do
      expect(BucketFileCache.instance).to be_a(BucketFileCache)
      expect(BucketFileCache.instance).to eq(BucketFileCache.instance)
    end
  end

  describe '#initialize' do
    it 'creates a cache directory' do
      expect(File.directory?(cache.cache_dir)).to be true
    end

    it 'starts a background thread' do
      expect(cache.instance_variable_get(:@thread)).to be_a(Thread)
    end
  end

  describe '.hint' do
    it 'adds bucket files to the queue' do
      BucketFileCache.hint(['path1', 'path2'])
      expect(cache.instance_variable_get(:@queued_bucket_files).size).to eq(2)
    end

    it 'sorts the queue by priority' do
      BucketFileCache.hint(['path2', 'path1'])
      queued_files = cache.instance_variable_get(:@queued_bucket_files)
      expect(queued_files[0].bucket_path).to eq('path1')
      expect(queued_files[1].bucket_path).to eq('path2')
    end
  end

  describe '.reserve' do
    it 'reserves a bucket file' do
      bucket_file = BucketFileCache.reserve('test_path')
      expect(bucket_file).to be_a(BucketFile)
      expect(bucket_file.reservation_count).to eq(1)
    end

    it 'retrieves the file from the bucket' do
      bucket_file = BucketFileCache.reserve('test_path')
      expect(File.exist?(bucket_file.local_path)).to be true
    end
  end

  describe '.unreserve' do
    it 'decreases the reservation count' do
      BucketFileCache.reserve('test_path')
      BucketFileCache.unreserve('test_path')
      bucket_file = cache.instance_variable_get(:@bucket_file_hash)['test_path']
      expect(bucket_file.reservation_count).to eq(0)
    end

    it 'removes the file from the cache when reservation count reaches 0' do
      BucketFileCache.reserve('test_path')
      BucketFileCache.unreserve('test_path')
      expect(cache.instance_variable_get(:@bucket_file_hash)['test_path']).to be_nil
    end
  end

  describe 'disk usage management' do
    it 'respects the maximum disk usage limit' do
      allow_any_instance_of(BucketFile).to receive(:size).and_return(500000) # 500 KB
      3.times { |i| BucketFileCache.reserve("test_path_#{i}") }
      expect(cache.instance_variable_get(:@current_disk_usage)).to be <= 1000000
    end
  end
end
```

This RSpec test program covers the main functionality of the BucketFileCache class. It includes tests for:

1. Singleton instance creation
2. Cache directory initialization
3. Background thread creation
4. Hinting functionality
5. Reserving and unreserving bucket files
6. File retrieval from the bucket
7. Disk usage management

Note that this test suite uses some mocking to avoid actual file system and network operations. You may need to adjust the mocks or add more sophisticated mocking if you want to test more specific scenarios or edge cases.

To run these tests, make sure you have RSpec installed (`gem install rspec`) and save this file with a `.rb` extension (e.g., `bucket_file_cache_spec.rb`). Then run the tests using the `rspec` command:

```
rspec bucket_file_cache_spec.rb
```

Remember to include the actual BucketFileCache class definition in the test file where indicated by the comment.

