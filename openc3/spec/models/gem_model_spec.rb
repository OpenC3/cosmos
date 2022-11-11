# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
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
      @orig_gem_home = ENV['GEM_HOME']
      @temp_dir = Dir.mktmpdir
      ENV['GEM_HOME'] = @temp_dir
      @scope = "DEFAULT"
      @gem_list = ['openc3-test1.gem', 'openc3-test2.gem']
      FileUtils.mkdir_p("#{ENV['GEM_HOME']}/cache")
      @gem_list.each do |gem|
        FileUtils.mkdir_p("#{ENV['GEM_HOME']}/gems/#{File.basename(gem, '.gem')}")
        FileUtils.touch("#{ENV['GEM_HOME']}/cache/#{gem}")
      end
    end

    after(:each) do
      FileUtils.remove_entry(@temp_dir) if @temp_dir and File.exist?(@temp_dir)
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
        expect(path).to eql "#{ENV['GEM_HOME']}/cache/openc3-test1.gem"
      end
    end

    describe "self.put" do
      it "raises if the gem doesn't exist" do
        expect { GemModel.put('another.gem', scope: 'DEFAULT') }.to raise_error(/does not exist/)
      end

      it "installs the gem to the gem server" do
        pm = class_double("OpenC3::ProcessManager").as_stubbed_const(:transfer_nested_constants => true)
        expect(pm).to receive_message_chain(:instance, :spawn)
        tf = Tempfile.new("openc3-test3.gem")
        tf.close
        GemModel.put(tf.path, scope: 'DEFAULT')
        tf.unlink
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
  end
end
