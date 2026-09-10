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

require "spec_helper"
require "ostruct"
require "zlib"
require "openc3/utilities/bucket_file_cache"

describe BucketFileCache do
  let(:prefix) { "DEFAULT/decom_logs/tlm/INST/20200101" }
  let(:bucket_path) { "#{prefix}/20200101000000000000000__20200101001000000000000__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin" }
  let(:bucket_path2) { "#{prefix}/20200101001000000000000__20200101002000000000000__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin" }
  let(:bucket_path3) { "#{prefix}/20200101002000000000000__20200101003000000000000__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin" }
  let(:contents) { 'x' * 100 }
  let(:file_size) { contents.length }

  before(:each) do
    @downloads = []
    @client = double("getClient").as_null_object
    allow(@client).to receive(:get_object) do |bucket:, key:, path:|
      @downloads << key
      FileUtils.mkdir_p(File.dirname(path))
      if File.extname(key) == '.gz'
        Zlib::GzipWriter.open(path) { |gz| gz.write(contents) }
      else
        File.write(path, contents)
      end
      OpenStruct.new
    end
    allow(OpenC3::Bucket).to receive(:getClient).and_return(@client)
    # Don't pay the retry backoff in tests
    allow_any_instance_of(BucketFile).to receive(:sleep)
    BucketFileCache.class_variable_set(:@@instance, nil)
    @caches = []
  end

  after(:each) do
    @caches.each do |cache|
      thread = cache.instance_variable_get(:@thread)
      if thread
        thread.kill
        thread.join
      end
      FileUtils.remove_dir(cache.cache_dir, true)
    end
    BucketFileCache.class_variable_set(:@@instance, nil)
  end

  # Build a cache and install it as the singleton. BucketFile#retrieve reaches
  # back through BucketFileCache.instance for cache_dir so the singleton has to
  # be set before anything downloads. The background thread is killed by
  # default so tests drive the cache deterministically.
  def build_cache(run_thread: false)
    cache = BucketFileCache.new
    @caches << cache
    BucketFileCache.class_variable_set(:@@instance, cache)
    unless run_thread
      thread = cache.instance_variable_get(:@thread)
      thread.kill
      thread.join
      cache.instance_variable_set(:@thread, nil)
    end
    cache
  end

  def hash(cache)
    cache.instance_variable_get(:@bucket_file_hash)
  end

  def queue(cache)
    cache.instance_variable_get(:@queued_bucket_files)
  end

  def disk_usage(cache)
    cache.instance_variable_get(:@current_disk_usage)
  end

  # Count linear scans of the download queue Array performed by the block.
  # Queue membership is checked once per file close in unreserve() and once per
  # cache entry in age_out_files(), so an Array#include? there is O(cache size)
  # on a hot path -- it has to be an O(1) lookup instead.
  def count_queue_scans(cache)
    scans = 0
    queue(cache).define_singleton_method(:include?) do |item|
      scans += 1
      super(item)
    end
    yield
    scans
  end

  # Poll rather than sleep a fixed amount so thread tests aren't slower than
  # they need to be. Returns whether the block came true before timing out.
  def wait_until(timeout = 5)
    start = Time.now
    while (Time.now - start) < timeout
      return true if yield
      sleep(0.05)
    end
    false
  end

  describe BucketFile do
    describe "initialize" do
      it "builds the topic prefix from the bucket path" do
        expect(BucketFile.new("DEFAULT/decom_logs/tlm/INST/x.bin").topic_prefix).to eql "DEFAULT__DECOM__{INST}"
        expect(BucketFile.new("DEFAULT/decom_logs/cmd/INST/x.bin").topic_prefix).to eql "DEFAULT__DECOMCMD__{INST}"
        expect(BucketFile.new("OTHER/raw_logs/tlm/INST2/x.bin").topic_prefix).to eql "OTHER__TELEMETRY__{INST2}"
        expect(BucketFile.new("OTHER/raw_logs/cmd/INST2/x.bin").topic_prefix).to eql "OTHER__COMMAND__{INST2}"
      end

      it "starts unreserved with no local file" do
        bucket_file = BucketFile.new(bucket_path)
        expect(bucket_file.bucket_path).to eql bucket_path
        expect(bucket_file.reservation_count).to eql 0
        expect(bucket_file.local_path).to be_nil
        expect(bucket_file.size).to eql 0
        expect(bucket_file.error).to be_nil
      end
    end

    describe "retrieve" do
      it "downloads the file and records its size" do
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        expect(bucket_file.retrieve(@client)).to be true
        expect(File.read(bucket_file.local_path)).to eql contents
        expect(bucket_file.size).to eql file_size
        expect(@downloads).to eql [bucket_path]
      end

      it "returns false and doesn't re-download an existing local file" do
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        expect(bucket_file.retrieve(@client)).to be true
        expect(bucket_file.retrieve(@client)).to be false
        expect(@downloads.length).to eql 1
      end

      it "uncompresses gzipped files and drops the .gz" do
        build_cache()
        bucket_file = BucketFile.new("#{bucket_path}.gz")
        expect(bucket_file.retrieve(@client)).to be true
        expect(File.extname(bucket_file.local_path)).to eql ".bin"
        expect(File.read(bucket_file.local_path)).to eql contents
        expect(bucket_file.size).to eql file_size
      end

      it "retries three times then raises and records the error" do
        build_cache()
        allow(@client).to receive(:get_object).and_raise("bucket down")
        bucket_file = BucketFile.new(bucket_path)
        expect { bucket_file.retrieve(@client) }.to raise_error(/bucket down/)
        expect(bucket_file.error.message).to match(/bucket down/)
        expect(bucket_file.local_path).to be_nil
      end
    end

    describe "reserve / unreserve" do
      it "counts reservations and deletes the local file at zero" do
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        expect(bucket_file.reserve).to be true
        expect(bucket_file.reservation_count).to eql 1
        local_path = bucket_file.local_path

        expect(bucket_file.reserve).to be false # already local
        expect(bucket_file.reservation_count).to eql 2

        expect(bucket_file.unreserve).to eql 1
        expect(File.exist?(local_path)).to be true

        expect(bucket_file.unreserve).to eql 0
        expect(File.exist?(local_path)).to be false
        expect(bucket_file.local_path).to be_nil
      end
    end

    describe "age_check" do
      it "keeps files that are young" do
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        bucket_file.retrieve(@client)
        expect(bucket_file.age_check).to be false
        expect(bucket_file.local_path).to_not be_nil
      end

      it "keeps old files that are still reserved" do
        stub_const("BucketFile::MAX_AGE_SECONDS", 0)
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        bucket_file.reserve
        expect(bucket_file.age_check).to be false
        expect(File.exist?(bucket_file.local_path)).to be true
      end

      it "deletes old files that are unreserved" do
        stub_const("BucketFile::MAX_AGE_SECONDS", 0)
        build_cache()
        bucket_file = BucketFile.new(bucket_path)
        bucket_file.retrieve(@client)
        local_path = bucket_file.local_path
        expect(bucket_file.age_check).to be true
        expect(File.exist?(local_path)).to be false
      end
    end
  end

  describe "instance" do
    it "returns the same singleton" do
      cache = BucketFileCache.instance
      @caches << cache
      expect(BucketFileCache.instance).to be cache
    end
  end

  describe "hint" do
    it "queues files in priority order without downloading them" do
      cache = build_cache()
      BucketFileCache.hint([bucket_path, bucket_path2, bucket_path3])
      expect(queue(cache).map(&:bucket_path)).to eql [bucket_path, bucket_path2, bucket_path3]
      expect(hash(cache).keys).to match_array [bucket_path, bucket_path2, bucket_path3]
      expect(@downloads).to be_empty
      expect(disk_usage(cache)).to eql 0
    end

    it "reuses files already in the cache" do
      cache = build_cache()
      BucketFileCache.hint([bucket_path])
      existing = hash(cache)[bucket_path]
      BucketFileCache.hint([bucket_path])
      expect(hash(cache).length).to eql 1
      expect(hash(cache)[bucket_path]).to be existing
      expect(queue(cache).length).to eql 1
    end
  end

  describe "reserve" do
    it "downloads the file, tracks disk usage, and dequeues it" do
      cache = build_cache()
      BucketFileCache.hint([bucket_path])
      bucket_file = BucketFileCache.reserve(bucket_path)
      expect(bucket_file.bucket_path).to eql bucket_path
      expect(bucket_file.reservation_count).to eql 1
      expect(File.exist?(bucket_file.local_path)).to be true
      expect(queue(cache)).to be_empty
      expect(disk_usage(cache)).to eql file_size
    end

    it "counts a second reservation of the same path only once against disk usage" do
      cache = build_cache()
      first = BucketFileCache.reserve(bucket_path)
      second = BucketFileCache.reserve(bucket_path)
      expect(second).to be first
      expect(first.reservation_count).to eql 2
      expect(@downloads.length).to eql 1
      expect(disk_usage(cache)).to eql file_size
    end
  end

  describe "unreserve" do
    # streaming_object_file_reader.rb and message_file_reader.rb both hand back
    # the BucketFile they got from reserve(), not its bucket path. Looking that
    # up in the path-keyed hash returned nil and the whole call did nothing.
    it "releases the reservation when given a BucketFile" do
      cache = build_cache()
      bucket_file = BucketFileCache.reserve(bucket_path)
      local_path = bucket_file.local_path

      BucketFileCache.unreserve(bucket_file)

      expect(bucket_file.reservation_count).to eql 0
      expect(File.exist?(local_path)).to be false
      expect(hash(cache)).to be_empty
      expect(disk_usage(cache)).to eql 0
    end

    it "releases the reservation when given a bucket path" do
      cache = build_cache()
      bucket_file = BucketFileCache.reserve(bucket_path)
      local_path = bucket_file.local_path

      BucketFileCache.unreserve(bucket_path)

      expect(bucket_file.reservation_count).to eql 0
      expect(File.exist?(local_path)).to be false
      expect(hash(cache)).to be_empty
      expect(disk_usage(cache)).to eql 0
    end

    it "keeps the file until every reservation is released" do
      cache = build_cache()
      bucket_file = BucketFileCache.reserve(bucket_path)
      BucketFileCache.reserve(bucket_path)

      BucketFileCache.unreserve(bucket_file)
      expect(File.exist?(bucket_file.local_path)).to be true
      expect(hash(cache).length).to eql 1
      expect(disk_usage(cache)).to eql file_size

      BucketFileCache.unreserve(bucket_file)
      expect(hash(cache)).to be_empty
      expect(disk_usage(cache)).to eql 0
    end

    it "ignores paths that aren't cached" do
      cache = build_cache()
      expect { BucketFileCache.unreserve("#{prefix}/not_cached.bin") }.to_not raise_error
      expect(disk_usage(cache)).to eql 0
    end

    it "leaves still-queued files in the cache" do
      cache = build_cache()
      # hint() queues both; reserving the first dequeues only that one, so the
      # second is still waiting on the download thread
      BucketFileCache.hint([bucket_path, bucket_path2])
      BucketFileCache.reserve(bucket_path)
      queued = hash(cache)[bucket_path2]

      BucketFileCache.unreserve(queued)

      # Dropping it here would orphan the size the download thread is about to add
      expect(hash(cache)).to have_key bucket_path2
      expect(queue(cache)).to eql [queued]
    end

    # The headline symptom: @current_disk_usage ratchets up until it passes
    # MAX_DISK_USAGE and the download thread stops fetching anything at all.
    it "does not leak disk usage or hash entries across many cycles" do
      cache = build_cache()
      20.times do |i|
        path = "#{prefix}/cycle_#{i}__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin"
        bucket_file = BucketFileCache.reserve(path)
        BucketFileCache.unreserve(bucket_file)
      end
      expect(hash(cache)).to be_empty
      expect(disk_usage(cache)).to eql 0
      expect(Dir.children(cache.cache_dir)).to be_empty
    end
  end

  describe "age out" do
    it "deletes old unreserved files and reclaims their disk usage" do
      stub_const("BucketFile::MAX_AGE_SECONDS", 0)
      cache = build_cache()
      bucket_file = BucketFileCache.reserve(bucket_path)
      local_path = bucket_file.local_path
      # Release the reservation without going through the cache so the entry
      # is left behind for the sweep to find
      bucket_file.instance_variable_set(:@reservation_count, 0)

      cache.age_out_files

      expect(hash(cache)).to be_empty
      expect(disk_usage(cache)).to eql 0
      expect(File.exist?(local_path)).to be false
    end

    it "keeps reserved files no matter how old" do
      stub_const("BucketFile::MAX_AGE_SECONDS", 0)
      cache = build_cache()
      bucket_file = BucketFileCache.reserve(bucket_path)

      cache.age_out_files

      expect(hash(cache).length).to eql 1
      expect(File.exist?(bucket_file.local_path)).to be true
      expect(disk_usage(cache)).to eql file_size
    end

    # A queued file's size is added by the download thread after the fact, so
    # dropping its hash entry here would orphan those bytes in @current_disk_usage
    it "skips files still waiting in the download queue" do
      stub_const("BucketFile::MAX_AGE_SECONDS", 0)
      cache = build_cache()
      BucketFileCache.hint([bucket_path])

      cache.age_out_files

      expect(hash(cache).length).to eql 1
      expect(queue(cache).length).to eql 1
    end
  end

  describe "queue membership cost" do
    # A historical query hints its whole file list, so both the queue and the
    # cache hold one entry per log file in the requested range
    it "does not rescan the download queue for every cache entry when aging out" do
      stub_const("BucketFile::MAX_AGE_SECONDS", 0)
      cache = build_cache()
      paths = (0...20).map { |i| "#{prefix}/scan_#{i}__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin" }
      BucketFileCache.hint(paths)
      # Reserve the first half, which dequeues them, then drop the reservations
      # so the sweep is free to take them
      swept = paths[0...10]
      swept.each do |path|
        BucketFileCache.reserve(path).instance_variable_set(:@reservation_count, 0)
      end

      scans = count_queue_scans(cache) { cache.age_out_files }

      expect(scans).to eql 0
      expect(hash(cache).keys).to match_array paths[10..]
      expect(queue(cache).length).to eql 10
    end

    it "does not scan the download queue on unreserve" do
      cache = build_cache()
      BucketFileCache.hint((0...20).map { |i| "#{prefix}/queued_#{i}__DEFAULT__INST__HEALTH_STATUS__rt__decom.bin" })
      bucket_file = BucketFileCache.reserve(bucket_path)

      scans = count_queue_scans(cache) { BucketFileCache.unreserve(bucket_file) }

      expect(scans).to eql 0
      expect(hash(cache)).to_not have_key bucket_path
    end

    it "keeps the queue index in step with the queue itself" do
      cache = build_cache(run_thread: true)
      BucketFileCache.hint([bucket_path, bucket_path2])
      expect(wait_until { queue(cache).empty? }).to be true
      # The download thread dequeued both, so neither is queued any longer
      expect(cache.instance_variable_get(:@queued_path_hash)).to be_empty
    end
  end

  describe "background thread" do
    it "downloads hinted files and tracks their disk usage" do
      cache = build_cache(run_thread: true)
      BucketFileCache.hint([bucket_path, bucket_path2])

      expect(wait_until { queue(cache).empty? and disk_usage(cache) == file_size * 2 }).to be true
      expect(@downloads).to match_array [bucket_path, bucket_path2]
    end

    # check_time was recomputed at the top of every loop iteration, so
    # Time.now > check_time was never true and the sweep never ran
    it "runs the age out sweep on the check interval" do
      stub_const("BucketFileCache::CHECK_TIME_SECONDS", 1)
      stub_const("BucketFile::MAX_AGE_SECONDS", 0)
      cache = build_cache(run_thread: true)
      BucketFileCache.hint([bucket_path])
      expect(wait_until { queue(cache).empty? and disk_usage(cache) == file_size }).to be true
      bucket_file = hash(cache)[bucket_path]
      expect(File.exist?(bucket_file.local_path)).to be true

      expect(wait_until { hash(cache).empty? }).to be true
      expect(disk_usage(cache)).to eql 0
      expect(bucket_file.local_path).to be_nil
    end

    it "stops downloading once disk usage passes MAX_DISK_USAGE" do
      stub_const("BucketFileCache::MAX_DISK_USAGE", file_size)
      cache = build_cache(run_thread: true)
      BucketFileCache.hint([bucket_path, bucket_path2, bucket_path3])

      expect(wait_until { disk_usage(cache) >= file_size }).to be true
      sleep(0.5) # Give the thread a chance to (wrongly) keep going
      expect(@downloads).to eql [bucket_path]
      expect(queue(cache).length).to eql 2
    end
  end
end
