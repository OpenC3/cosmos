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

require "spec_helper"
require "openc3/utilities/ruby_lex_utils"

module OpenC3
  describe RubyLexUtils do
    before(:each) do
      @lex = RubyLexUtils.new
    end

    describe "contains_begin?" do
      it "detects the begin keyword" do
        expect(@lex.contains_begin?("  begin  ")).to be true
        expect(@lex.contains_begin?("  begin # asdf  ")).to be true
      end
    end

    describe "contains_keyword?" do
      it "detects the ruby keywords" do
        expect(@lex.contains_keyword?("if something")).to be true
        expect(@lex.contains_keyword?("obj.method = something")).to be false
      end
    end

    describe "contains_block_beginning?" do
      it "detects block beginning keywords" do
        expect(@lex.contains_block_beginning?("do")).to be true
        expect(@lex.contains_block_beginning?("[].each {")).to be true
        expect(@lex.contains_block_beginning?("begin")).to be true
      end
    end

    describe "remove_comments" do
      it "removes comments" do
        text = <<~DOC
          # This is a comment
          blah = 5 # Inline comment
          # Another
        DOC
        expect(@lex.remove_comments(text)).to eql "\nblah = 5 \n\n"
      end
    end

    describe "each_lexed_segment" do
      it "yields each segment" do
        text = <<~DOC
          begin
            x = 0
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["begin\n", false, true, 1], # can't instrument begin
          ["  x = 0\n", true, true, 2],
          ["end\n", false, false, 3]
        ) # can't instrument end
      end

      it "handles multiple begins" do
        text = <<~DOC
          z = 5
          begin
            a = 0
            begin
              x = 0
            rescue
              x = 1
            end
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["z = 5\n", true, false, 1],
          ["begin\n", false, true, 2], # can't instrument begin
          ["  a = 0\n", true, true, 3],
          ["  begin\n", false, true, 4],
          ["    x = 0\n", true, true, 5],
          ["  rescue\n", false, true, 6],
          ["    x = 1\n", true, true, 7],
          ["  end\n", false, true, 8],
          ["end\n", false, false, 9]
        ) # can't instrument end
      end

      it "handles multiline segments" do
        text = <<~DOC
          a = [10,
          11,
          12,
          13,
          14]
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["a = [10,\n11,\n12,\n13,\n14]\n", true, false, 1]
        )
      end

      it "handles complex hash segments" do
        text = <<~DOC
          { :X1 => 1,
            :X2 => 2
          }.each {|x, y| puts x}
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["{ :X1 => 1,\n  :X2 => 2\n}.each {|x, y| puts x}\n", false, false, 1]
        )
      end

      it "handles even more complex hash and array segments" do
        text = <<~DOC
          limits = {
            'val' => {
              'val Voltage' => {
                'tlm_name'        => 'target packet item',
                'metric'          => 'V',
                'requirement_id'  => nil,
                'off_limits'      => {
                    'yellow_lower'  => nil,
                    'red_lower'     => nil
                },
                'on_limits'       => {
                    'red_lower'     => 1,
                    'yellow_lower'  => 1,
                    'yellow_upper'  => 1,
                    'red_upper'     => 1
                }
              }
            }
          }
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["limits = {\n" +
          "  'val' => {\n" +
          "    'val Voltage' => {\n" +
          "      'tlm_name'        => 'target packet item',\n" +
          "      'metric'          => 'V',\n" +
          "      'requirement_id'  => nil,\n" +
          "      'off_limits'      => {\n" +
          "          'yellow_lower'  => nil,\n" +
          "          'red_lower'     => nil\n" +
          "      },\n" +
          "      'on_limits'       => {\n" +
          "          'red_lower'     => 1,\n" +
          "          'yellow_lower'  => 1,\n" +
          "          'yellow_upper'  => 1,\n" +
          "          'red_upper'     => 1\n" +
          "      }\n" +
          "    }\n" +
          "  }\n" +
          "}\n", true, false, 1]
        )

        text = <<~DOC
          array = [
            1, 2, 3,
            4,
            [
              5, 6, 7
            ],
            {
              'tlm_name'        => 'target packet item',
              'metric'          => 'V',
              'requirement_id'  => nil,
              'off_limits'      => {
                  'yellow_lower'  => nil,
                  'red_lower'     => nil
              },
            }
          ]
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["array = [\n" +
          "  1, 2, 3,\n" +
          "  4,\n" +
          "  [\n" +
          "    5, 6, 7\n" +
          "  ],\n" +
          "  {\n" +
          "    'tlm_name'        => 'target packet item',\n" +
          "    'metric'          => 'V',\n" +
          "    'requirement_id'  => nil,\n" +
          "    'off_limits'      => {\n" +
          "        'yellow_lower'  => nil,\n" +
          "        'red_lower'     => nil\n" +
          "    },\n" +
          "  }\n" +
          "]\n", true, false, 1]
        )
      end

      it "handles a multiline string" do
        text = <<~DOC
        screen =
        "
          SCREEN AUTO AUTO 1.0

          LABELVALUE INST HEALTH_STATUS TEMP1
          LABELVALUE INST HEALTH_STATUS TEMP2
        "

        local_screen("INST", screen)
        DOC

        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["screen =\n" +
          "\"\n" +
          "  SCREEN AUTO AUTO 1.0\n" +
          "\n" +
          "  LABELVALUE INST HEALTH_STATUS TEMP1\n" +
          "  LABELVALUE INST HEALTH_STATUS TEMP2\n" +
          "\"\n", true, false, 1],
          ["\n", true, false, 8],
          ["local_screen(\"INST\", screen)\n", true, false, 9]
        )
      end

      it "yields each segment" do
        text = <<~DOC

                    if x
                    y
                    else
                    z
                    end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["\n", true, false, 1],
          ["if x\n", false, false, 2], # can't instrument if
          ["y\n", true, false, 3],
          ["else\n", false, false, 4], # can't instrument else
          ["z\n", true, false, 5],
          ["end\n", false, false, 6]
        )  # can't instrument end
      end

      it "handles a larger script" do
        text = <<~DOC
          collects = tlm("INST HEALTH_STATUS COLLECTS")
          cmd("INST COLLECT with TYPE NORMAL, DURATION 1.0")
          wait_check("INST HEALTH_STATUS COLLECTS > \#{collects}", 5)

          begin
            loop do
              puts 'hi'
            end
          rescue
            puts 'error'
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["collects = tlm(\"INST HEALTH_STATUS COLLECTS\")\n", true, false, 1],
          ["cmd(\"INST COLLECT with TYPE NORMAL, DURATION 1.0\")\n", true, false, 2],
          ["wait_check(\"INST HEALTH_STATUS COLLECTS > \#{collects}\", 5)\n", true, false, 3],
          ["\n", true, false, 4],
          ["begin\n", false, true, 5],
          ["  loop do\n", false, true, 6],
          ["    puts 'hi'\n", true, true, 7],
          ["  end\n", false, true, 8],
          ["rescue\n", false, true, 9],
          ["  puts 'error'\n", true, true, 10],
          ["end\n", false, false, 11]
        )
      end

      it "handles fancy single line statements" do
        text = <<~DOC
          begin; raise 'death'; rescue; puts 'rescued'; end
          puts 'outside begin'
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["begin; raise 'death'; rescue; puts 'rescued'; end\n", false, false, 1],
          ["puts 'outside begin'\n", true, false, 2]
        )

        text = <<~DOC
          begin
          raise 'death'
          rescue; puts 'rescued'; end
          puts 'outside begin'
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["begin\n", false, true, 1],
          ["raise 'death'\n", true, true, 2],
          ["rescue; puts 'rescued'; end\n", false, false, 3],
          ["puts 'outside begin'\n", true, false, 4]
        )
      end

      it "handles classes" do
        text = <<~DOC
          class Test
            def instance_method(variable)
              puts variable
              if variable
                puts 'another puts'
              end
            end

            def self.class_method(variable, keyword:)
              begin
                puts variable
              rescue
                puts keyword
              end
            end
          end

          test = Test.new
          test.instance_method(1)
          Test.class_method(2, keyword: 'Test')
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["class Test\n", false, false, 1],
          ["  def instance_method(variable)\n", false, false, 2],
          ["    puts variable\n", true, false, 3],
          ["    if variable\n", false, false, 4],
          ["      puts 'another puts'\n", true, false, 5],
          ["    end\n", false, false, 6],
          ["  end\n", false, false, 7],
          ["\n", true, false, 8],
          ["  def self.class_method(variable, keyword:)\n", false, false, 9],
          ["    begin\n", false, true, 10],
          ["      puts variable\n", true, true, 11],
          ["    rescue\n", false, true, 12],
          ["      puts keyword\n", true, true, 13],
          ["    end\n", false, false, 14],
          ["  end\n", false, false, 15],
          ["end\n", false, false, 16],
          ["\n", true, false, 17],
          ["test = Test.new\n", true, false, 18],
          ["test.instance_method(1)\n", true, false, 19],
          ["Test.class_method(2, keyword: 'Test')\n", true, false, 20]
        )

        text = <<~DOC
        class Test
          def instance_method(
            variable1,
            variable2,
            variable3,
            variable4
          )
            puts variable1
          end
        end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["class Test\n", false, false, 1],
          ["  def instance_method(\n" +
          "    variable1,\n" +
          "    variable2,\n" +
          "    variable3,\n" +
          "    variable4\n" +
          "  )\n", false, false, 2],
          ["    puts variable1\n", true, false, 8],
          ["  end\n", false, false, 9],
          ["end\n", false, false, 10]
        )
      end

      it "handles weird spacing" do
        text = <<~DOC
                    if true
                      if false
              puts 'hi'
        end
                    end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["            if true\n", false, false, 1],
          ["              if false\n", false, false, 2],
          ["      puts 'hi'\n", true, false, 3],
          ["end\n", false, false, 4],
          ["            end\n", false, false, 5]
        )
      end
    end
  end
end
