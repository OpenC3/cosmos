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
require 'openc3/utilities/secrets'
require 'fileutils'
require 'tmpdir'

module OpenC3
  describe Secrets do
    before(:each) do
      @saved_dir = ENV['OPENC3_SECRET_FILE_DIR']
      ENV['OPENC3_SECRET_FILE_DIR'] = nil
    end

    after(:each) do
      ENV['OPENC3_SECRET_FILE_DIR'] = @saved_dir
    end

    describe "secret_file_dir" do
      it "defaults to /tmp" do
        expect(Secrets.secret_file_dir()).to eql '/tmp'
      end

      it "uses OPENC3_SECRET_FILE_DIR" do
        ENV['OPENC3_SECRET_FILE_DIR'] = '/var/secrets'
        expect(Secrets.secret_file_dir()).to eql '/var/secrets'
      end

      it "ignores a blank OPENC3_SECRET_FILE_DIR" do
        ENV['OPENC3_SECRET_FILE_DIR'] = ''
        expect(Secrets.secret_file_dir()).to eql '/tmp'
      end
    end

    describe "validate_file_path" do
      it "allows paths under the secret file dir" do
        expect(Secrets.validate_file_path('/tmp/DATA/cert')).to eql '/tmp/DATA/cert'
        expect(Secrets.validate_file_path('/tmp/INST/MQTT_KEY')).to eql '/tmp/INST/MQTT_KEY'
      end

      it "normalizes the returned path" do
        expect(Secrets.validate_file_path('/tmp/DATA/./sub/../cert')).to eql '/tmp/DATA/cert'
      end

      it "rejects absolute paths outside the secret file dir" do
        ['/root/.ssh/id_rsa', '/etc/shadow', '/etc/passwd', '/openc3/lib/openc3.rb'].each do |path|
          expect { Secrets.validate_file_path(path) }.to raise_error(ArgumentError, /must be under/)
        end
      end

      it "rejects traversal out of the secret file dir" do
        ['/tmp/../etc/passwd', '/tmp/a/../../etc/passwd', '/tmp/../../etc/passwd'].each do |path|
          expect { Secrets.validate_file_path(path) }.to raise_error(ArgumentError, /must be under/)
        end
      end

      it "rejects relative paths" do
        expect { Secrets.validate_file_path('../../openc3-cosmos-cmd-tlm-api/config/secrets.yml') }.to raise_error(ArgumentError, /must be under/)
      end

      it "rejects the secret file dir itself" do
        expect { Secrets.validate_file_path('/tmp') }.to raise_error(ArgumentError, /must be under/)
        expect { Secrets.validate_file_path('/tmp/') }.to raise_error(ArgumentError, /must be under/)
      end

      it "rejects a symlink pointing outside the secret file dir" do
        link = "/tmp/openc3_secrets_spec_link_#{Process.pid}"
        FileUtils.rm_f(link)
        File.symlink('/etc/passwd', link)
        begin
          expect { Secrets.validate_file_path(link) }.to raise_error(ArgumentError, /must be under/)
        ensure
          FileUtils.rm_f(link)
        end
      end

      it "rejects a symlinked directory pointing outside the secret file dir" do
        link = "/tmp/openc3_secrets_spec_dir_#{Process.pid}"
        FileUtils.rm_f(link)
        File.symlink('/etc', link)
        begin
          expect { Secrets.validate_file_path("#{link}/passwd") }.to raise_error(ArgumentError, /must be under/)
        ensure
          FileUtils.rm_f(link)
        end
      end

      it "rejects a dangling symlink pointing outside the secret file dir" do
        # The operator opens the path for writing, which follows a dangling
        # symlink and creates the file it points at
        link = "/tmp/openc3_secrets_spec_dangling_#{Process.pid}"
        FileUtils.rm_f(link)
        File.symlink('/etc/openc3_secrets_spec_does_not_exist', link)
        begin
          expect { Secrets.validate_file_path(link) }.to raise_error(ArgumentError, /broken or circular symlink/)
        ensure
          FileUtils.rm_f(link)
        end
      end

      it "rejects a dangling symlink in the middle of the path" do
        link = "/tmp/openc3_secrets_spec_dangling_dir_#{Process.pid}"
        FileUtils.rm_f(link)
        File.symlink('/etc/openc3_secrets_spec_does_not_exist', link)
        begin
          expect { Secrets.validate_file_path("#{link}/cert") }.to raise_error(ArgumentError, /broken or circular symlink/)
        ensure
          FileUtils.rm_f(link)
        end
      end

      it "allows a not yet created file in a not yet created directory" do
        expect(Secrets.validate_file_path('/tmp/openc3_secrets_spec_no_such_dir/cert')).to eql '/tmp/openc3_secrets_spec_no_such_dir/cert'
      end

      it "rejects blank, non String, and null byte paths" do
        expect { Secrets.validate_file_path('') }.to raise_error(ArgumentError, /blank/)
        expect { Secrets.validate_file_path('   ') }.to raise_error(ArgumentError, /blank/)
        expect { Secrets.validate_file_path(nil) }.to raise_error(ArgumentError, /must be a String/)
        expect { Secrets.validate_file_path("/tmp/cert\x00/etc/passwd") }.to raise_error(ArgumentError, /null byte/)
      end

      it "honors OPENC3_SECRET_FILE_DIR" do
        Dir.mktmpdir do |dir|
          ENV['OPENC3_SECRET_FILE_DIR'] = dir
          expect(Secrets.validate_file_path("#{dir}/cert")).to eql "#{dir}/cert"
          expect { Secrets.validate_file_path('/tmp/DATA/cert') }.to raise_error(ArgumentError, /must be under/)
        end
      end
    end

    describe "setup" do
      it "requires at least 3 items" do
        expect { Secrets.new.setup([['ENV', 'KEY']]) }.to raise_error(ArgumentError, /at least 3 items/)
      end

      it "raises on unknown types" do
        expect { Secrets.new.setup([['OTHER', 'KEY', 'DATA']]) }.to raise_error(/Unknown secret type/)
      end

      it "reads ENV secrets" do
        ENV['OPENC3_SECRETS_SPEC'] = 'value'
        secrets = Secrets.new
        secrets.setup([['ENV', 'KEY', 'OPENC3_SECRETS_SPEC']])
        expect(secrets.get('KEY', scope: 'DEFAULT')).to eql 'value'
        ENV['OPENC3_SECRETS_SPEC'] = nil
      end

      it "reads FILE secrets under the secret file dir" do
        path = "/tmp/openc3_secrets_spec_#{Process.pid}"
        File.write(path, 'secret value')
        begin
          secrets = Secrets.new
          secrets.setup([['FILE', 'KEY', path]])
          expect(secrets.get('KEY', scope: 'DEFAULT')).to eql 'secret value'
        ensure
          FileUtils.rm_f(path)
        end
      end

      it "does not read FILE secrets outside the secret file dir" do
        expect { Secrets.new.setup([['FILE', 'KEY', '/etc/passwd']]) }.to raise_error(ArgumentError, /must be under/)
        expect { Secrets.new.setup([['FILE', 'KEY', '/tmp/../etc/passwd']]) }.to raise_error(ArgumentError, /must be under/)
      end
    end
  end
end
