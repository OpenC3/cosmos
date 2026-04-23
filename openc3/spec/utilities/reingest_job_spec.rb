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
require 'openc3/utilities/reingest_job'

module OpenC3
  describe ReingestJob do
    before(:each) do
      mock_redis()
      setup_system()

      ENV['OPENC3_LOGS_BUCKET'] = 'logs'

      # Create the backing job record
      @job_id = 'test-job-1'
      @model = ReingestJobModel.new(
        name: @job_id,
        files: ['sample.bin.gz'],
        bucket: 'OPENC3_LOGS_BUCKET',
        path: 'DEFAULT/raw_logs/tlm/INST/',
        scope: 'DEFAULT',
      )
      @model.create

      # Stub bucket access: get_object must actually create the file on disk
      @bucket_client = double('BucketClient').as_null_object
      allow(Bucket).to receive(:getClient).and_return(@bucket_client)
      allow(@bucket_client).to receive(:get_object) do |args|
        FileUtils.touch(args[:path])
      end
      allow(BucketUtilities).to receive(:uncompress_file) do |path|
        decompressed = path.sub(/\.gz\z/, '')
        FileUtils.touch(decompressed)
        decompressed
      end

      # Target configs are loaded by setup_system above; stub the setup_targets
      # call so it doesn't try to download zips from the stubbed bucket.
      allow(System).to receive(:setup_targets)
      allow(System).to receive(:reset_instance!)

      # Stub QuestDB ALTER statements
      @conn = double('PGConn')
      allow(QuestDBClient).to receive(:connection).and_return(@conn)
      @alter_sql = []
      allow(@conn).to receive(:exec) { |sql| @alter_sql << sql }
      # DEDUP status query returns "not enabled" by default
      result = double('PGResult', ntuples: 0)
      allow(@conn).to receive(:exec_params).and_return(result)

      # Stub the PacketLogReader to yield a single packet
      packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      allow_any_instance_of(PacketLogReader).to receive(:each) do |_reader, _file, _identify, &block|
        block.call(packet)
      end

      # Stub DecomCommon so we can verify what it's called with
      allow(DecomCommon).to receive(:decom_and_publish).and_return(1)
    end

    def run_job(cooldown: 0, target_version: 'as_logged')
      ReingestJob.new(
        job_id: @job_id,
        files: ['sample.bin.gz'],
        path: 'DEFAULT/raw_logs/tlm/INST/',
        bucket: 'OPENC3_LOGS_BUCKET',
        scope: 'DEFAULT',
        target_version: target_version,
        dedup_cooldown_seconds: cooldown,
      ).run
    end

    def stub_reader_with_target_id(hex_id)
      # Simulate what PacketLogReader does internally: accumulate binary
      # target ids into @target_ids during file parsing. We set it directly
      # since the mocked `each` bypasses the real parsing.
      binary_id = hex_id ? [hex_id].pack('H*') : nil
      allow_any_instance_of(PacketLogReader).to receive(:each) do |reader, _file, _identify, &block|
        reader.instance_variable_set(:@target_ids, binary_id ? [binary_id] : [])
        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        block.call(packet)
      end
    end

    it 'transitions state from Queued to Complete' do
      run_job
      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
      expect(reloaded.finished_at).not_to be_nil
      expect(reloaded.packets_written).to be >= 1
    end

    it 'loads the target configs parsed from the reingest path' do
      expect(System).to receive(:setup_targets)
        .with(['INST'], anything, hash_including(scope: 'DEFAULT'))
      run_job
    end

    it 'skips target loading when the path is not a raw_logs path' do
      expect(System).not_to receive(:setup_targets)
      ReingestJob.new(
        job_id: @job_id,
        files: ['sample.bin.gz'],
        path: 'some/custom/path/',
        bucket: 'OPENC3_LOGS_BUCKET',
        scope: 'DEFAULT',
        dedup_cooldown_seconds: 0,
      ).run
    end

    context 'target_version' do
      it "passes 'current' to setup_targets when target_version is 'current'" do
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: 'current'))
        run_job(target_version: 'current')
      end

      it "uses the embedded file hash when target_version is 'as_logged'" do
        hash = 'abcdef1234567890' * 4
        stub_reader_with_target_id(hash)
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: hash))
        run_job(target_version: 'as_logged')
      end

      it "falls back to 'current' for 'as_logged' files that have no hash" do
        stub_reader_with_target_id(nil)
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: 'current'))
        run_job(target_version: 'as_logged')
      end

      it 'uses an explicit hash value for every file when passed directly' do
        hash = 'c' * 64
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: hash))
        run_job(target_version: hash)
      end

      it "falls back to 'current' when the requested hash archive is missing" do
        hash = 'd' * 64
        stub_reader_with_target_id(hash)

        call_count = 0
        allow(System).to receive(:setup_targets) do |_targets, _dir, kwargs|
          call_count += 1
          raise Errno::ENOENT, "archive missing" if kwargs[:target_version] == hash
          # 'current' succeeds on the fallback call
        end

        run_job(target_version: 'as_logged')

        reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
        expect(reloaded.state).to eql('Complete')
        expect(reloaded.warnings).to include(a_string_matching(/Version '#{hash}' archive missing/))
        expect(call_count).to eql(2) # hash attempt + current fallback
      end

      it "skips the group and records warnings when 'current' fallback also fails" do
        hash = 'e' * 64
        stub_reader_with_target_id(hash)
        allow(System).to receive(:setup_targets).and_raise(Errno::ENOENT, 'all gone')

        run_job(target_version: 'as_logged')

        reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
        # No System was loaded so nothing ingested, but we don't crash the job
        # — other groups (if any) should still get a chance. Warnings record
        # the double failure so the UI can surface it.
        expect(reloaded.warnings.length).to eql(2)
        expect(reloaded.warnings.last).to match(/'current' also failed/)
        expect(reloaded.packets_written).to eql(0)
      end

      it "propagates the error when the user explicitly requested 'current' and it fails" do
        stub_reader_with_target_id(nil) # no embedded hash → as_logged maps to 'current'
        allow(System).to receive(:setup_targets).and_raise(Errno::ENOENT, 'gone')

        run_job(target_version: 'current')

        reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
        expect(reloaded.state).to eql('Crashed')
      end

      it 'rebuilds System once per distinct file hash' do
        hash_a = 'a' * 64
        hash_b = 'b' * 64
        call_count = 0
        allow_any_instance_of(PacketLogReader).to receive(:each) do |reader, file, _identify, &block|
          call_count += 1
          binary_id = [file.include?('second') ? hash_b : hash_a].pack('H*')
          reader.instance_variable_set(:@target_ids, [binary_id])
          packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
          packet.received_time = Time.now.sys
          block.call(packet)
        end
        # Two files so we exercise the per-hash grouping.
        @files = ['first.bin.gz', 'second.bin.gz']
        @model.files = @files
        @model.update
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: hash_a)).ordered
        expect(System).to receive(:setup_targets)
          .with(['INST'], anything, hash_including(target_version: hash_b)).ordered
        expect(System).to receive(:reset_instance!).twice

        ReingestJob.new(
          job_id: @job_id,
          files: @files,
          path: 'DEFAULT/raw_logs/tlm/INST/',
          bucket: 'OPENC3_LOGS_BUCKET',
          scope: 'DEFAULT',
          target_version: 'as_logged',
          dedup_cooldown_seconds: 0,
        ).run

        reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
        expect(reloaded.versions_used).to contain_exactly(hash_a, hash_b)
      end
    end

    it 'calls DecomCommon.decom_and_publish with check_limits: false' do
      run_job
      expect(DecomCommon).to have_received(:decom_and_publish).with(
        anything,
        hash_including(scope: 'DEFAULT', check_limits: false),
      )
    end

    it 'enables DEDUP before ingest and disables it after cooldown' do
      run_job
      enables = @alter_sql.grep(/DEDUP ENABLE/)
      disables = @alter_sql.grep(/DEDUP DISABLE/)
      expect(enables.length).to eql(1)
      expect(disables.length).to eql(1)
      expect(enables.first).to include('DEFAULT__TLM__INST__HEALTH_STATUS')
      expect(disables.first).to include('DEFAULT__TLM__INST__HEALTH_STATUS')
      # The ENABLE must precede the DISABLE
      expect(@alter_sql.index(enables.first)).to be < @alter_sql.index(disables.first)
    end

    it 'does not disable DEDUP for tables that were already enabled' do
      # Return DEDUP = true for the status query
      result = double('PGResult', ntuples: 1)
      allow(result).to receive(:[]).with(0).and_return({ 'dedup' => true })
      allow(@conn).to receive(:exec_params).and_return(result)

      run_job
      # We didn't enable it, so we don't disable it
      expect(@alter_sql.grep(/DEDUP ENABLE/)).to be_empty
      expect(@alter_sql.grep(/DEDUP DISABLE/)).to be_empty

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.dedup_preexisting).to include('DEFAULT__TLM__INST__HEALTH_STATUS')
      expect(reloaded.dedup_enabled_by_us).to be_empty
    end

    it 'still disables DEDUP on crash (ensure block)' do
      allow(DecomCommon).to receive(:decom_and_publish).and_raise('boom')

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Crashed')
      expect(reloaded.error).to eql('boom')
      expect(@alter_sql.grep(/DEDUP DISABLE/)).not_to be_empty
    end

    it 'records the error when the crash cleanup disable itself fails' do
      # First connection call (enable) succeeds; second (disable during crash
      # cleanup) raises before even entering the loop, so disable_dedup itself
      # propagates and trips the outer rescue in run().
      connection_calls = 0
      allow(QuestDBClient).to receive(:connection) do
        connection_calls += 1
        raise RuntimeError, 'pg connection dropped' if connection_calls >= 2
        @conn
      end
      allow(DecomCommon).to receive(:decom_and_publish).and_raise('ingest failed')
      expect(Logger).to receive(:error).with(/failed to disable DEDUP during crash cleanup/).at_least(:once)
      allow(Logger).to receive(:error) # swallow the primary crash log

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Crashed')
      expect(reloaded.error).to eql('ingest failed')
      expect(reloaded.dedup_disabled_tables).to be_empty
    end

    it 'handles non-.gz files without decompressing' do
      # Replace the stub from `before` to simulate a plain .bin file.
      allow_any_instance_of(PacketLogReader).to receive(:each) do |_r, _f, _i, &block|
        packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        block.call(packet)
      end
      expect(BucketUtilities).not_to receive(:uncompress_file)

      job = ReingestJob.new(
        job_id: @job_id,
        files: ['sample.bin'], # no .gz
        path: 'DEFAULT/raw_logs/tlm/INST/',
        bucket: 'OPENC3_LOGS_BUCKET',
        scope: 'DEFAULT',
        dedup_cooldown_seconds: 0,
      )
      job.run

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
    end

    it 'warns and skips when DEDUP enable fails' do
      allow(@conn).to receive(:exec) do |sql|
        @alter_sql << sql
        raise RuntimeError, 'enable failed' if sql.include?('DEDUP ENABLE')
      end

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
      expect(reloaded.dedup_enabled_by_us).to be_empty
      # Without anything enabled by us, disable loop runs over empty list
      expect(@alter_sql.grep(/DEDUP DISABLE/)).to be_empty
    end

    it 'treats DEDUP status query errors as not-enabled' do
      allow(@conn).to receive(:exec_params).and_raise('query failed')

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
      # Query error → assume not enabled → we enable it, then disable after cooldown
      expect(reloaded.dedup_enabled_by_us).to include('DEFAULT__TLM__INST__HEALTH_STATUS')
      expect(reloaded.dedup_disabled_tables).to include('DEFAULT__TLM__INST__HEALTH_STATUS')
    end

    it 'warns but continues when DEDUP disable fails' do
      allow(@conn).to receive(:exec) do |sql|
        @alter_sql << sql
        raise RuntimeError, 'disable failed' if sql.include?('DEDUP DISABLE')
      end

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
      expect(reloaded.dedup_disabled_tables).to be_empty
      # The ALTER was still attempted
      expect(@alter_sql.grep(/DEDUP DISABLE/)).not_to be_empty
    end

    it 'ticks the heartbeat during the cooldown sleep' do
      job = ReingestJob.new(
        job_id: @job_id,
        files: ['sample.bin.gz'],
        path: 'DEFAULT/raw_logs/tlm/INST/',
        bucket: 'OPENC3_LOGS_BUCKET',
        scope: 'DEFAULT',
        dedup_cooldown_seconds: 2, # short but > 0
      )
      allow(job).to receive(:sleep) # skip the actual wait
      job.run

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.state).to eql('Complete')
      expect(job).to have_received(:sleep).at_least(:once)
    end

    it 'throttles per-packet status writes during ingest' do
      # Yield many packets so the throttle (every 500) fires
      packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      allow_any_instance_of(PacketLogReader).to receive(:each) do |_r, _f, _i, &block|
        550.times { block.call(packet) }
      end

      run_job

      reloaded = ReingestJobModel.get_model(name: @job_id, scope: 'DEFAULT')
      expect(reloaded.packets_written).to eql(550)
    end
  end
end
