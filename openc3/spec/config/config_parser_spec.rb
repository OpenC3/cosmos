# encoding: utf-8

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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/config/config_parser'
require 'tempfile'
require 'tmpdir'

module OpenC3
  describe ConfigParser do
    before(:each) do
      @cp = ConfigParser.new
      ConfigParser.message_callback = nil
      ConfigParser.progress_callback = nil
    end

    describe "parse_file", no_ext: true do
      it "yields keyword, parameters to the block" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'PARAM2', 'PARAM 3')
          expect(@cp.line).to eql line
          expect(@cp.line_number).to eql 1
        end
        tf.unlink
      end

      it "handles Ruby string interpolation" do
        tf = Tempfile.new('unittest')
        tf.puts 'KEYWORD1 #{var} PARAM1'
        tf.puts 'KEYWORD2 PARAM1 #Comment'
        tf.close

        results = {}
        @cp.parse_file(tf.path) do |keyword, params|
          results[keyword] = params
        end

        expect(results.keys).to eql %w(KEYWORD1 KEYWORD2)
        expect(results["KEYWORD1"]).to eql %w(#{var} PARAM1)
        expect(results["KEYWORD2"]).to eql %w(PARAM1)
        tf.unlink
      end

      it "supports ERB syntax" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD <%= 5 * 2 %>"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params[0]).to eql "10"
        end
        tf.unlink
      end

      it "ignores commented out ERB syntax" do
        tf = Tempfile.new('unittest')
        tf.puts "# KEYWORD <%= raise 'boom' %>"
        tf.puts "# <%= render '_ccsds_cmd.txt', locals: {id: 4} %>"
        tf.puts "# KEYWORD <% if true %>"
        tf.puts "# KEYWORD <% raise 'dead' %>"
        tf.puts "# KEYWORD <% end %>"
        tf.puts "OTHER stuff"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "OTHER"
          expect(params[0]).to eql "stuff"
        end
        tf.unlink
      end

      it "requires ERB partials begin with an underscore" do
        tf = Tempfile.new('unittest')
        tf.puts "<%= render 'partial.txt' %>"
        tf.close

        expect { @cp.parse_file(tf.path) }.to raise_error(ConfigParser::Error, /must begin with an underscore/)
        tf.unlink
      end

      it "allows ERB partials in subdirectories" do
        Dir.mktmpdir("partial_dir") do |dir|
          tf2 = Tempfile.new('_partial.txt', dir)
          tf2.puts "SUBDIR"
          tf2.close
          tf = Tempfile.new('unittest')
          # Grab the sub directory name plus filename
          subdir_path = tf2.path().split('/')[-2..-1].join('/')
          tf.puts "<%= render '#{subdir_path}' %>"
          tf.close

          @cp.parse_file(tf.path) do |keyword, _params|
            expect(keyword).to eql "SUBDIR"
          end
          tf.unlink
          tf2.unlink
        end
      end

      it "allows absolute paths to ERB partials" do
        Dir.mktmpdir("partial_dir") do |dir|
          tf2 = Tempfile.new('_partial.txt', dir)
          tf2.puts "ABSOLUTE"
          tf2.close
          tf = Tempfile.new('unittest')
          tf.puts "<%= render '#{tf2.path}' %>"
          tf.close

          @cp.parse_file(tf.path) do |keyword, _params|
            expect(keyword).to eql "ABSOLUTE"
          end
          tf.unlink
          tf2.unlink
        end
      end

      it "supports ERB partials via render" do
        tf2 = Tempfile.new('_partial.txt')
        tf2.puts '<% if output %> # comment ©'
        tf2.puts 'RENDER <%= id %> <%= desc %>'
        tf2.puts '<% end %>'
        tf2.puts '# comment ®' # UTF-8 chars
        tf2.close

        # Run the test twice to verify the KEYWORD gets rendered and then doesn't
        [true, false].each do |output|
          tf = Tempfile.new('unittest')
          tf.puts "<%= render '#{File.basename(tf2.path)}', locals: {id: 1, desc: 'Description', output: #{output}} %> # comment €"
          tf.close

          yielded = false
          @cp.parse_file(tf.path) do |keyword, params|
            yielded = true
            expect(keyword).to eql "RENDER"
            expect(params[0]).to eql "1"
            expect(params[1]).to eql "Description"
          end
          expect(yielded).to eql output
          tf.unlink
        end
        tf2.unlink
      end

      it "optionally does not remove quotes" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path, false, false) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'PARAM2', "'PARAM 3'")
          expect(@cp.line).to eql line
          expect(@cp.line_number).to eql 1
        end
        tf.unlink
      end

      it "handles inline line continuations" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 & PARAM2"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to eql %w(PARAM1 & PARAM2)
          expect(@cp.line).to eql "KEYWORD PARAM1 & PARAM2"
          expect(@cp.line_number).to eql 1
        end
        tf.unlink
      end

      it "handles line continuations as EOL" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 &"
        tf.puts "  PARAM2 'PARAM 3'"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'PARAM2', 'PARAM 3')
          expect(@cp.line).to eql "KEYWORD PARAM1 PARAM2 'PARAM 3'"
          expect(@cp.line_number).to eql 2
        end

        @cp.parse_file(tf.path, false, false) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'PARAM2', "'PARAM 3'")
          expect(@cp.line).to eql "KEYWORD PARAM1 PARAM2 'PARAM 3'"
          expect(@cp.line_number).to eql 2
        end
        tf.unlink
      end

      it "handles line continuations without another line" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 &"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1')
          expect(@cp.line).to eql "KEYWORD PARAM1"
          expect(@cp.line_number).to eql 1
        end
        tf.unlink
      end

      it "handles line continuations with a comment line" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 &"
        tf.puts "# Comment"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1')
          expect(@cp.line).to eql "KEYWORD PARAM1 # Comment"
          expect(@cp.line_number).to eql 2
        end
        tf.unlink
      end

      it "handles string concatenations" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 'continues ' \\"
        tf.puts "'next line'"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'continues next line')
          expect(@cp.line).to eql "KEYWORD PARAM1 'continues next line'"
          expect(@cp.line_number).to eql 2
        end

        @cp.parse_file(tf.path, false, false) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', "'continues next line'")
          expect(@cp.line).to eql "KEYWORD PARAM1 'continues next line'"
          expect(@cp.line_number).to eql 2
        end
        tf.unlink
      end

      it "handles bad string concatenations" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 'continues ' \\"
        tf.puts "" # blank line
        tf.puts "KEYWORD2 PARAM2" # forces this into the first line
        tf.close
        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', "'continues", 'EYWORD2', 'PARAM2')
          expect(@cp.line).to eql "KEYWORD PARAM1 'continues EYWORD2 PARAM2"
          expect(@cp.line_number).to eql 3
        end
        tf.unlink

        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 'continues ' \\"
        tf.puts "next line" # Forgot quotes
        tf.puts "KEYWORD2 PARAM2" # Ensure we process the next line
        tf.close
        @cp.parse_file(tf.path) do |keyword, params|
          if keyword == 'KEYWORD'
            expect(keyword).to eql "KEYWORD"
            expect(params).to include('PARAM1', "'continues", "ext", "line")
            # Works but creates weird open quote with no close quote
            expect(@cp.line).to eql "KEYWORD PARAM1 'continues ext line"
            expect(@cp.line_number).to eql 2
          else
            expect(keyword).to eql "KEYWORD2"
            expect(params).to include('PARAM2')
            expect(@cp.line).to eql "KEYWORD2 PARAM2"
            expect(@cp.line_number).to eql 3
          end
        end
        tf.unlink
      end

      it "handles string concatenations with newlines" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD PARAM1 'continues ' +"
        tf.puts "# Comment line which is ignored"
        tf.puts "'next line'"
        tf.close

        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', "continues \nnext line")
          expect(@cp.line).to eql "KEYWORD PARAM1 'continues \nnext line'"
          expect(@cp.line_number).to eql 3
        end

        @cp.parse_file(tf.path, false, false) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', "'continues \nnext line'")
          expect(@cp.line).to eql "KEYWORD PARAM1 'continues \nnext line'"
          expect(@cp.line_number).to eql 3
        end
        tf.unlink
      end

      it "optionally yields comment lines" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD1 PARAM1"
        tf.puts "# This is a comment"
        tf.puts "KEYWORD2 PARAM1"
        tf.close

        lines = []
        @cp.parse_file(tf.path, true) do |_keyword, _params|
          lines << @cp.line
        end
        expect(lines).to include("# This is a comment")
        tf.unlink
      end

      it "callbacks for messages" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD PARAM1 PARAM2 'PARAM 3'"
        tf.puts line
        tf.close

        msg_callback = double(:call => true)
        expect(msg_callback).to receive(:call).once.with(/Parsing .* bytes of .*#{File.basename(tf.path)}/)

        ConfigParser.message_callback = msg_callback
        @cp.parse_file(tf.path) do |keyword, params|
          expect(keyword).to eql "KEYWORD"
          expect(params).to include('PARAM1', 'PARAM2', 'PARAM 3')
          expect(@cp.line).to eql line
          expect(@cp.line_number).to eql 1
        end
        tf.unlink
      end

      it "callbacks for percent done" do
        tf = Tempfile.new('unittest')
        # Callback is made at beginning, every 10 lines, and at the end
        15.times { tf.puts "KEYWORD PARAM" }
        tf.close

        msg_callback = double(:call => true)
        done_callback = double(:call => true)
        expect(done_callback).to receive(:call).with(0.0)
        expect(done_callback).to receive(:call).with(0.6)
        expect(done_callback).to receive(:call).with(1.0)

        ConfigParser.message_callback = msg_callback
        ConfigParser.progress_callback = done_callback
        @cp.parse_file(tf.path) { |k, p| }
        tf.unlink
      end
    end

    describe "verify_num_parameters" do
      it "verifies the minimum number of parameters" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path) do |keyword, _params|
          expect(keyword).to eql "KEYWORD"
          expect { @cp.verify_num_parameters(1, 1) }.to raise_error(ConfigParser::Error, "Not enough parameters for KEYWORD.")
        end
        tf.unlink
      end

      it "verifies the maximum number of parameters" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD PARAM1 PARAM2"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path) do |keyword, _params|
          expect(keyword).to eql "KEYWORD"
          expect { @cp.verify_num_parameters(1, 1) }.to raise_error(ConfigParser::Error, "Too many parameters for KEYWORD.")
        end
        tf.unlink
      end
    end

    describe "verify_parameter_naming" do
      it "verifies parameters do not have bad characters" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD BAD1_ BAD__2 'BAD 3' }BAD_4 BAD[[5]]"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path) do |_keyword, _params|
          expect { @cp.verify_parameter_naming(1) }.to raise_error(ConfigParser::Error, /cannot end with an underscore/)
          expect { @cp.verify_parameter_naming(2) }.to raise_error(ConfigParser::Error, /cannot contain a double underscore/)
          expect { @cp.verify_parameter_naming(3) }.to raise_error(ConfigParser::Error, /cannot contain a space/)
          expect { @cp.verify_parameter_naming(4) }.to raise_error(ConfigParser::Error, /cannot start with a close bracket/)
          expect { @cp.verify_parameter_naming(5) }.to raise_error(ConfigParser::Error, /cannot contain double brackets/)
        end
        tf.unlink
      end
    end

    describe "error" do
      it "returns an Error" do
        tf = Tempfile.new('unittest')
        line = "KEYWORD"
        tf.puts line
        tf.close

        @cp.parse_file(tf.path) do |_keyword, _params|
          error = @cp.error("Hello")
          expect(error.message).to eql "Hello"
          expect(error.keyword).to eql "KEYWORD"
          expect(error.filename).to eql tf.path
        end
        tf.unlink
      end
    end

    describe "error handling" do
      it "collects all errors and returns all" do
        tf = Tempfile.new('unittest')
        tf.puts "KEYWORD1"
        tf.puts "KEYWORD2"
        tf.puts "KEYWORD3"
        tf.close

        expect {
          @cp.parse_file(tf.path) do |keyword, _params|
            if keyword == "KEYWORD1"
              raise @cp.error("Invalid KEYWORD1")
            end
            if keyword == "KEYWORD3"
              raise @cp.error("Invalid KEYWORD3")
            end
          end
        }.to raise_error(/.*:1: KEYWORD1\n.*Error: Invalid KEYWORD1(\n|.)*:3: KEYWORD3\n.*Error: Invalid KEYWORD3/)
        tf.unlink
      end
    end

    describe "self.handle_nil" do
      it "converts 'NIL' and 'NULL' to nil" do
        expect(ConfigParser.handle_nil('NIL')).to be_nil
        expect(ConfigParser.handle_nil('NULL')).to be_nil
        expect(ConfigParser.handle_nil('nil')).to be_nil
        expect(ConfigParser.handle_nil('null')).to be_nil
        expect(ConfigParser.handle_nil('')).to be_nil
      end

      it "returns nil with nil" do
        expect(ConfigParser.handle_nil(nil)).to be_nil
      end

      it "returns values that don't convert" do
        expect(ConfigParser.handle_nil("HI")).to eql "HI"
        expect(ConfigParser.handle_nil(5.0)).to eql 5.0
      end
    end

    describe "self.handle_true_false" do
      it "converts 'TRUE' and 'FALSE'" do
        expect(ConfigParser.handle_true_false('TRUE')).to be true
        expect(ConfigParser.handle_true_false('FALSE')).to be false
        expect(ConfigParser.handle_true_false('true')).to be true
        expect(ConfigParser.handle_true_false('false')).to be false
      end

      it "passes through true and false" do
        expect(ConfigParser.handle_true_false(true)).to be true
        expect(ConfigParser.handle_true_false(false)).to be false
      end

      it "returns values that don't convert" do
        expect(ConfigParser.handle_true_false("HI")).to eql "HI"
        expect(ConfigParser.handle_true_false(5.0)).to eql 5.0
      end
    end

    describe "self.handle_true_false_nil" do
      it "converts 'NIL' and 'NULL' to nil" do
        expect(ConfigParser.handle_true_false_nil('NIL')).to be_nil
        expect(ConfigParser.handle_true_false_nil('NULL')).to be_nil
        expect(ConfigParser.handle_true_false_nil('nil')).to be_nil
        expect(ConfigParser.handle_true_false_nil('null')).to be_nil
        expect(ConfigParser.handle_true_false_nil('')).to be_nil
      end

      it "returns nil with nil" do
        expect(ConfigParser.handle_true_false_nil(nil)).to be_nil
      end

      it "converts 'TRUE' and 'FALSE'" do
        expect(ConfigParser.handle_true_false_nil('TRUE')).to be true
        expect(ConfigParser.handle_true_false_nil('FALSE')).to be false
        expect(ConfigParser.handle_true_false_nil('true')).to be true
        expect(ConfigParser.handle_true_false_nil('false')).to be false
      end

      it "passes through true and false" do
        expect(ConfigParser.handle_true_false_nil(true)).to be true
        expect(ConfigParser.handle_true_false_nil(false)).to be false
      end

      it "returns values that don't convert" do
        expect(ConfigParser.handle_true_false("HI")).to eql "HI"
        expect(ConfigParser.handle_true_false(5.0)).to eql 5.0
      end
    end

    describe "self.handle_defined_constants" do
      it "converts string constants to numbers" do
        (1..64).each do |val|
          # Unsigned
          expect(ConfigParser.handle_defined_constants("MIN", :UINT, val)).to eql 0
          expect(ConfigParser.handle_defined_constants("MAX", :UINT, val)).to eql((2**val) - 1)
          # Signed
          expect(ConfigParser.handle_defined_constants("MIN", :INT, val)).to eql(-(2**val) / 2)
          expect(ConfigParser.handle_defined_constants("MAX", :INT, val)).to eql(((2**val) / 2) - 1)
        end
        [8, 16, 32, 64].each do |val|
          # Unsigned
          expect(ConfigParser.handle_defined_constants("MIN_UINT#{val}")).to eql 0
          expect(ConfigParser.handle_defined_constants("MAX_UINT#{val}")).to eql((2**val) - 1)
          # Signed
          expect(ConfigParser.handle_defined_constants("MIN_INT#{val}")).to eql(-(2**val) / 2)
          expect(ConfigParser.handle_defined_constants("MAX_INT#{val}")).to eql(((2**val) / 2) - 1)
        end
        # Float
        expect(ConfigParser.handle_defined_constants("MIN_FLOAT32")).to be <= -3.4 * (10**38)
        expect(ConfigParser.handle_defined_constants("MAX_FLOAT32")).to be >= 3.4 * (10**38)
        expect(ConfigParser.handle_defined_constants("MIN_FLOAT64")).to eql(-Float::MAX)
        expect(ConfigParser.handle_defined_constants("MAX_FLOAT64")).to eql Float::MAX
        expect(ConfigParser.handle_defined_constants("POS_INFINITY")).to eql Float::INFINITY
        expect(ConfigParser.handle_defined_constants("NEG_INFINITY")).to eql(-Float::INFINITY)
      end

      it "complains about undefined strings" do
        expect { ConfigParser.handle_defined_constants("TRUE") }.to raise_error(ArgumentError, "Could not convert constant: TRUE")
      end

      it "passes through numbers" do
        expect(ConfigParser.handle_defined_constants(0)).to eql 0
        expect(ConfigParser.handle_defined_constants(0.0)).to eql 0.0
      end
    end
  end
end
