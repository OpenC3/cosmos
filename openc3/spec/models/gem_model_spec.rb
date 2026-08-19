# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'tempfile'
require 'ostruct'
require 'openc3/models/plugin_model'
require 'openc3/models/gem_model'
require 'openc3/utilities/aws_bucket'
require 'fileutils'

module OpenC3
  describe GemModel do
    before(:each) do
      mock_redis()
      @orig_gem_home = ENV.fetch('GEM_HOME', nil)
      @temp_dir = Dir.mktmpdir
      ENV['GEM_HOME'] = @temp_dir
      @scope = "DEFAULT"
      @gem_list = ['openc3-test1.gem', 'openc3-test2.gem']
      FileUtils.mkdir_p("#{ENV.fetch('GEM_HOME')}/cache")
      @gem_list.each do |gem|
        FileUtils.mkdir_p("#{ENV.fetch('GEM_HOME')}/gems/#{File.basename(gem, '.gem')}")
        FileUtils.touch("#{ENV.fetch('GEM_HOME')}/cache/#{gem}")
      end
    end

    after(:each) do
      FileUtils.remove_entry_secure(@temp_dir, true)
      @temp_dir = nil
      ENV['GEM_HOME'] = @orig_gem_home
    end

    describe "self.names" do
      it "returns a list of gem names" do
        expect(GemModel.names).to eql ["openc3-test1.gem", "openc3-test2.gem"]
      end
    end

    describe "self.get" do
      it "get the gem on the local filesystem" do
        path = GemModel.get('openc3-test1.gem')
        expect(path).to eql "#{ENV.fetch('GEM_HOME')}/cache/openc3-test1.gem"
      end
    end

    describe "self.put" do
      it "raises if the gem doesn't exist" do
        expect { GemModel.put('another.gem', scope: 'DEFAULT') }.to raise_error(/does not exist/)
      end

      it "puts the gem to the gem server" do
        pm = class_double("OpenC3::ProcessManager").as_stubbed_const(:transfer_nested_constants => true)
        result = double("fakepm")
        expect(result).to receive(:name).and_return("1234__56")
        expect(pm).to receive_message_chain(:instance, :spawn).and_return(result)
        tf = Tempfile.new("openc3-test3.gem")
        tf.close
        GemModel.put(tf.path, scope: 'DEFAULT')
        tf.unlink
      end
    end

    describe "self.install" do
      it "existing gemfile and handles missing" do
        expect { GemModel.install("openc3-test1.gem", scope: 'DEFAULT') }.to \
          raise_error(Gem::Package::FormatError, /package metadata is missing/)
        expect { GemModel.install("openc3-test3.gem", scope: 'DEFAULT') }.to \
          raise_error(RuntimeError, /Gem 'openc3-test3.gem' not found/)
      end

      context "rubygems_url resolution" do
        # The gem itself is invalid so install always raises, but Gem.sources is
        # set before that happens which is what we're verifying
        def install_test_gem
          expect { GemModel.install("openc3-test1.gem", scope: 'DEFAULT') }.to \
            raise_error(Gem::Package::FormatError)
        end

        it "uses the rubygems_url setting" do
          allow(GemModel).to receive(:get_setting).with('rubygems_url', scope: 'DEFAULT')
            .and_return("https://gems.example.com")
          expect(Gem).to receive(:sources=).with(["https://gems.example.com"])
          install_test_gem()
        end

        it "replaces an invalid rubygems_url setting with the default" do
          allow(GemModel).to receive(:get_setting).with('rubygems_url', scope: 'DEFAULT')
            .and_return("https://rubygems.org ; id > /tmp/PWNED ; #")
          allow(Logger).to receive(:error)
          expect(Gem).to receive(:sources=).with([RubygemsUrl::DEFAULT])
          install_test_gem()
          expect(Logger).to have_received(:error).with(/Invalid rubygems_url/)
        end

        it "doesn't set sources when the setting is nil" do
          allow(GemModel).to receive(:get_setting).with('rubygems_url', scope: 'DEFAULT').and_return(nil)
          expect(Gem).to_not receive(:sources=)
          install_test_gem()
        end

        it "falls back to ENV RUBYGEMS_URL when get_setting raises" do
          allow(GemModel).to receive(:get_setting).with('rubygems_url', scope: 'DEFAULT')
            .and_raise(RuntimeError.new("no redis"))
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with('RUBYGEMS_URL', RubygemsUrl::DEFAULT)
            .and_return("https://env.gems.example.com")
          expect(Gem).to receive(:sources=).with(["https://env.gems.example.com"])
          install_test_gem()
        end

        it "falls back to the default when get_setting raises and ENV is unset" do
          allow(GemModel).to receive(:get_setting).with('rubygems_url', scope: 'DEFAULT')
            .and_raise(RuntimeError.new("no redis"))
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with('RUBYGEMS_URL', RubygemsUrl::DEFAULT).and_return(RubygemsUrl::DEFAULT)
          expect(Gem).to receive(:sources=).with([RubygemsUrl::DEFAULT])
          install_test_gem()
        end
      end
    end

    describe "self.destroy" do
      it "removes the gem from the gem server" do
        uninstaller = instance_double("Gem::Uninstaller").as_null_object
        expect(Gem::Uninstaller).to receive(:new).and_return(uninstaller)
        expect(uninstaller).to receive(:uninstall)
        GemModel.destroy("openc3-test1.gem")
      end
    end

    describe "self.destroy_all_other_versions" do
      it "removes the gem from the gem server" do
        uninstaller = instance_double("Gem::Uninstaller").as_null_object
        expect(Gem::Uninstaller).to receive(:new).and_return(uninstaller)
        expect(uninstaller).to receive(:uninstall)
        GemModel.destroy_all_other_versions("openc3-test1.gem")
      end
    end
  end
end
