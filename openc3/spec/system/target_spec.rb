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
require 'openc3'
require 'openc3/system/target'
require 'tempfile'
require 'pathname'
require 'fileutils'

module OpenC3
  describe Target do
    after(:all) do
      FileUtils.rm_rf File.join(OpenC3::USERPATH, 'target_spec_temp')
    end

    describe "initialize" do
      it "creates a target with the given name" do
        expect(Target.new("TGT", 'path').name).to eql "TGT"
      end

      it "creates a target with the specified dir" do
        expect(Target.new("TGT", '/path').dir).to eql File.join('/path', 'TGT')
      end

      it "creates a target with a gem path" do
        saved = File.join(OpenC3::USERPATH, 'saved')
        expect(Target.new("TGT", '/path', saved).dir).to eql saved
      end

      it "records all the command and telemetry files in the target directory" do
        tgt_name = "TEST"
        tgt_path = File.join(OpenC3::USERPATH, 'target_spec_temp', tgt_name)
        cmd_tlm = File.join(tgt_path, 'cmd_tlm')
        FileUtils.mkdir_p(cmd_tlm)
        File.open(File.join(cmd_tlm, 'cmd1.txt'), 'w') {}
        File.open(File.join(cmd_tlm, 'cmd2.txt'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm1.txt'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm2.txt'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm2.txt~'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm2.txt.mine'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm3.xtce'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm3.xtce~'), 'w') {}
        File.open(File.join(cmd_tlm, 'tlm3.xtce.bak'), 'w') {}

        tgt = Target.new(tgt_name, nil, tgt_path)
        expect(tgt.dir).to eql tgt_path
        files = Dir[File.join(cmd_tlm, '*.txt')]
        files.concat(Dir[File.join(cmd_tlm, '*.xtce')])
        expect(files).not_to be_empty
        expect(tgt.cmd_tlm_files.length).to eql 5
        expect(tgt.cmd_tlm_files.sort).to eql files.sort

        FileUtils.rm_r(tgt_path)
      end

      it "processes a target.txt in the target directory" do
        tgt_name = "TEST"
        tgt_path = File.join(OpenC3::USERPATH, 'target_spec_temp', tgt_name)
        FileUtils.mkdir_p(tgt_path)
        File.open(File.join(tgt_path, 'target.txt'), 'w') do |file|
          file.puts("IGNORE_PARAMETER TEST")
        end

        tgt = Target.new(tgt_name, nil, tgt_path)
        expect(tgt.dir).to eql tgt_path
        expect(tgt.ignored_parameters).to eql ["TEST"]

        FileUtils.rm_r(tgt_path)
      end
    end

    describe "process_file" do
      it "complains about unknown keywords" do
        tf = Tempfile.new('unittest')
        tf.puts("BLAH")
        tf.close
        expect { Target.new("TGT", '/path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Unknown keyword 'BLAH'/)
        tf.unlink
      end

      context "with REQUIRE" do
        it "complains with 0 parameters" do
          tf = Tempfile.new('unittest')
          tf.puts("REQUIRE")
          tf.close
          expect { Target.new("INST", '/path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for REQUIRE./)
          tf.unlink
        end

        it "complains with more than 1 parameter" do
          tf = Tempfile.new('unittest')
          tf.puts("REQUIRE my_file.rb TRUE")
          tf.close
          expect { Target.new("INST", '/path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for REQUIRE./)
          tf.unlink
        end

        it "complains if the file doesn't exist" do
          tf = Tempfile.new('unittest')
          tf.puts("REQUIRE my_file.rb")
          tf.close
          expect { Target.new("INST", '/path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Unable to require my_file.rb/)
          tf.unlink
        end

        it "requires a file with absolute path" do
          filename = File.join(OpenC3::USERPATH, 'abs_path.rb')
          File.open(filename, 'w') do |file|
            file.puts "class AbsPath"
            file.puts "end"
          end
          tf = Tempfile.new('unittest')
          tf.puts("REQUIRE #{File.expand_path(filename)}")
          tf.close

          # Initial require in target lib shouldn't be reported as error
          expect(Logger).to_not receive(:error)
          Target.new("INST", '/path').process_file(tf.path)
          expect { AbsPath.new }.to_not raise_error
          File.delete filename
          tf.unlink
        end
      end

      context "with IGNORE_PARAMETER" do
        it "takes 1 parameters" do
          tf = Tempfile.new('unittest')
          tf.puts("IGNORE_PARAMETER")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for IGNORE_PARAMETER./)
          tf.unlink

          tf = Tempfile.new('unittest')
          tf.puts("IGNORE_PARAMETER my_file.rb TRUE")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for IGNORE_PARAMETER./)
          tf.unlink
        end

        it "stores the parameter" do
          tf = Tempfile.new('unittest')
          tf.puts("IGNORE_PARAMETER TEST")
          tf.close
          tgt = Target.new("TGT", 'path')
          tgt.process_file(tf.path)
          expect(tgt.ignored_parameters).to eql ["TEST"]
          tf.unlink
        end
      end

      context "with COMMANDS and TELEMETRY" do
        it "takes 1 parameters" do
          tf = Tempfile.new('unittest')
          tf.puts("COMMANDS")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for COMMANDS./)
          tf.unlink

          tf = Tempfile.new('unittest')
          tf.puts("COMMANDS tgt_cmds.txt TRUE")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for COMMANDS./)
          tf.unlink

          tf = Tempfile.new('unittest')
          tf.puts("TELEMETRY")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Not enough parameters for TELEMETRY./)
          tf.unlink

          tf = Tempfile.new('unittest')
          tf.puts("TELEMETRY tgt_tlm.txt TRUE")
          tf.close
          expect { Target.new("TGT", 'path').process_file(tf.path) }.to raise_error(ConfigParser::Error, /Too many parameters for TELEMETRY./)
          tf.unlink
        end

        it "stores the filename" do
          tgt_path = File.join(OpenC3::USERPATH, 'target_spec_temp')
          tgt_name = "TEST"
          tgt_dir = File.join(tgt_path, tgt_name)
          FileUtils.mkdir_p(tgt_dir)
          FileUtils.mkdir_p(tgt_dir + '/cmd_tlm')
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds3.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm3.txt', 'w') { |file| file.puts "# comment" }
          File.open(File.join(tgt_dir, 'target.txt'), 'w') do |file|
            file.puts("COMMANDS tgt_cmds2.txt")
            file.puts("TELEMETRY tgt_tlm3.txt")
          end

          tgt = Target.new(tgt_name, nil, tgt_dir)
          expect(tgt.dir).to eql tgt_dir
          expect(tgt.cmd_tlm_files.length).to eql 2
          expect(tgt.cmd_tlm_files).to eql [tgt_dir + '/cmd_tlm/tgt_cmds2.txt', tgt_dir + '/cmd_tlm/tgt_tlm3.txt']

          FileUtils.rm_r(tgt_dir)
        end

        it "filenames must exist" do
          tgt_path = File.join(OpenC3::USERPATH, 'target_spec_temp')
          tgt_name = "TEST"
          tgt_dir = File.join(tgt_path, tgt_name)
          FileUtils.mkdir_p(tgt_dir)
          FileUtils.mkdir_p(tgt_dir + '/cmd_tlm')
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds3.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm3.txt', 'w') { |file| file.puts "# comment" }
          File.open(File.join(tgt_dir, 'target.txt'), 'w') do |file|
            file.puts("COMMANDS tgt_cmds4.txt")
            file.puts("TELEMETRY tgt_tlm4.txt")
          end

          expect { Target.new(tgt_name, nil, tgt_dir) }.to raise_error(ConfigParser::Error, /#{tgt_dir + '/cmd_tlm/tgt_cmds4.txt'} not found/)

          FileUtils.rm_r(tgt_dir)
        end

        it "filename order must be preserved" do
          tgt_path = File.join(OpenC3::USERPATH, 'target_spec_temp')
          tgt_name = "TEST"
          tgt_dir = File.join(tgt_path, tgt_name)
          FileUtils.mkdir_p(tgt_dir)
          FileUtils.mkdir_p(tgt_dir + '/cmd_tlm')
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_cmds3.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm2.txt', 'w') { |file| file.puts "# comment" }
          File.open(tgt_dir + '/cmd_tlm/tgt_tlm3.txt', 'w') { |file| file.puts "# comment" }
          File.open(File.join(tgt_dir, 'target.txt'), 'w') do |file|
            file.puts("COMMANDS tgt_cmds3.txt")
            file.puts("COMMANDS tgt_cmds2.txt")
            file.puts("TELEMETRY tgt_tlm3.txt")
            file.puts("TELEMETRY tgt_tlm.txt")
          end

          tgt = Target.new(tgt_name, nil, tgt_dir)
          expect(tgt.dir).to eql tgt_dir
          expect(tgt.cmd_tlm_files.length).to eql 4
          expect(tgt.cmd_tlm_files).to eql [tgt_dir + '/cmd_tlm/tgt_cmds3.txt', tgt_dir + '/cmd_tlm/tgt_cmds2.txt', tgt_dir + '/cmd_tlm/tgt_tlm3.txt', tgt_dir + '/cmd_tlm/tgt_tlm.txt']

          FileUtils.rm_rf(tgt_dir)
        end
      end
    end
  end
end
