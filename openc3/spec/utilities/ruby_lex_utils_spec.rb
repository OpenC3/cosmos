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

    describe "each_lexed_segment" do
      it "yields each segment" do
        text = <<~DOC
          =begin
          This is a comment
          So is this
          =end
          begin
            x = 0
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["begin\n", false, true, 5], # can't instrument begin
          ["  x = 0\n", true, true, 6],
          ["end\n", false, false, 7] # can't instrument end
        )
      end

      it "handles puts" do
        text = <<~DOC
          # Initial comment
          puts "HI"
            # This is a comment
            # block
            puts ENV.inspect
          puts('YES') # So is this
          pp ENV
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["\n", true, false, 1],
          ["puts \"HI\"\n", true, false, 2],
          ["  \n", true, false, 3],
          ["  \n", true, false, 4],
          ["  puts ENV.inspect\n", true, false, 5],
          ["puts('YES') \n", true, false, 6],
          ["pp ENV\n", true, false, 7]
        )
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
          ["{ :X1 => 1,\n" +
           "  :X2 => 2\n" +
           "}.each {|x, y| puts x}\n", false, false, 1]
        )
      end

      it "handles complex hash segments" do
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
      end

      it "handles complex array segments" do
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

      it "handles 1 line raise" do
        text = <<~DOC
          raise "Bad return" unless result == 'CHOICE1' or result == 'CHOICE2'
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["raise \"Bad return\" unless result == 'CHOICE1' or result == 'CHOICE2'\n", false, false, 1],
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
                      unless false
              puts 'hi'
        end
                    end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["            if true\n", false, false, 1],
          ["              unless false\n", false, false, 2],
          ["      puts 'hi'\n", true, false, 3],
          ["end\n", false, false, 4],
          ["            end\n", false, false, 5]
        )
      end

      it "handles a line break in a cmd" do
        text = <<~DOC
          cmd("INST COLLECT with TYPE \#{type},
            DURATION \#{duration}")
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["cmd(\"INST COLLECT with TYPE \#{type},\n"+
           "  DURATION \#{duration}\")\n", true, false, 1],
        )
      end

      it "handles multiple lines included string interpolation" do
        text = <<~DOC
          definition = "
            SCREEN AUTO AUTO 1.0
              VERTICALBOX 'Test Screen'
              LABELVALUE \#{target} \#{packet} \#{item}
            END"
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["definition = \"\n"+
           "  SCREEN AUTO AUTO 1.0\n"+
           "    VERTICALBOX 'Test Screen'\n"+
           "    LABELVALUE \#{target} \#{packet} \#{item}\n"+
           "  END\"\n", true, false, 1]
        )
      end

      it "handles block beginnings" do
        text = <<~DOC
          array = [1, 2, 3]
          array.each do |value|
            puts value
          end
          array.each {
            puts "an item"
          }
          begin
            puts "another"
          rescue Exception => err
            puts err
          end
          begin; puts "in begin"
          rescue; puts "in rescue"
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["array = [1, 2, 3]\n", true, false, 1],
          ["array.each do |value|\n", false, false, 2],
          ["  puts value\n", true, false, 3],
          ["end\n", false, false, 4],
          ["array.each {\n  puts \"an item\"\n}\n", false, false, 5],
          ["begin\n", false, true, 8],
          ["  puts \"another\"\n", true, true, 9],
          ["rescue Exception => err\n", false, true, 10],
          ["  puts err\n", true, true, 11],
          ["end\n", false, false, 12],
          ["begin; puts \"in begin\"\n", false, true, 13],
          ["rescue; puts \"in rescue\"\n", false, true, 14],
          ["end\n", false, false, 15],
        )
      end

      it "handles complex structures between methods" do
        text = <<~DOC
          def method1
            a = "part1" +
              "part2"
          end

          def method2
            a = 5
          end
        DOC
        expect { |b| @lex.each_lexed_segment(text, &b) }.to yield_successive_args(
          ["def method1\n", false, false, 1],
          ["  a = \"part1\" +\n    \"part2\"\n", true, false, 2],
          ["end\n", false, false, 4],
          ["\n", true, false, 5],
          ["def method2\n", false, false, 6],
          ["  a = 5\n", true, false, 7],
          ["end\n", false, false, 8],
        )
      end

      it "has reasonable performance" do
        #require 'ruby-prof'

        # profile the code
        #RubyProf.start

        text1 = "class MyBigClass\n"
        text3 = "end\n"

        big_text = text1
        1000.times do |count|
          text2 = <<~DOC
            def a_great_method_#{count} (arg1, arg2, key: true)
              if key
                return arg1 + arg2
              else
                begin
                  if (arg1 / arg2) > arg2
                    raise "Oh No!"
                  end
                rescue
                  puts "Oh well"
                end
              end
            end
          DOC

          big_text << text2
        end
        big_text << text3
        #line_count = big_text.count("\n")

        start_time = Time.now
        filename = 'test.rb'

        # Below matches use in ScriptRunner's running_script#instrument_script_implementation
        instrumented_text = ''
        @lex.each_lexed_segment(big_text) do |segment, instrumentable, inside_begin, line_no|
          instrumented_line = ''
          if instrumentable
            # Add a newline if it's empty to ensure the instrumented code has
            # the same number of lines as the original script. Note that the
            # segment could have originally had comments but they were stripped in
            # ruby_lex_utils.remove_comments
            if segment.strip.empty?
              instrumented_text << "\n"
              next
            end

            # Create a variable to hold the segment's return value
            instrumented_line << "__return_val = nil; "

            # If not inside a begin block then create one to catch exceptions
            unless inside_begin
              instrumented_line << 'begin; '
            end

            # Add preline instrumentation
            instrumented_line << "RunningScript.instance.script_binding = binding(); "\
              "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); "

            # Add the actual line
            instrumented_line << "__return_val = begin; "
            instrumented_line << segment
            instrumented_line.chomp!

            # Add postline instrumentation
            instrumented_line << " end; RunningScript.instance.post_line_instrumentation('#{filename}', #{line_no}); "

            # Complete begin block to catch exceptions
            unless inside_begin
              instrumented_line << "rescue Exception => eval_error; "\
              "retry if RunningScript.instance.exception_instrumentation(eval_error, '#{filename}', #{line_no}); end; "
            end

            instrumented_line << " __return_val\n"
          else
            unless segment =~ /^\s*end\s*$/ or segment =~ /^\s*when .*$/
              num_left_brackets = segment.count('{')
              num_right_brackets = segment.count('}')
              num_left_square_brackets = segment.count('[')
              num_right_square_brackets = segment.count(']')

              if (num_right_brackets > num_left_brackets) ||
                (num_right_square_brackets > num_left_square_brackets)
                instrumented_line = segment
              else
                instrumented_line = "RunningScript.instance.pre_line_instrumentation('#{filename}', #{line_no}); " + segment
              end
            else
              instrumented_line = segment
            end
          end

          instrumented_text << instrumented_line
        end

        end_time = Time.now

        # ... code to profile ...
        #result = RubyProf.stop

        # print a flat profile to text
        #printer = RubyProf::FlatPrinter.new(result)
        #printer.print(STDOUT)

        # puts "Instrumented #{line_count} lines in #{end_time - start_time} seconds"
        expect(end_time - start_time).to be <= 8.0
      end

      it "has reasonable performance test 2" do
        tf = Tempfile.new('blah.rb')
        begin
          tf.puts "class Blah"
          400.times do
            name = ('a'..'z').to_a.shuffle[0,8].join
            tf.puts "def #{name}"
            tf.puts 'cmd("INST COLLECT with TYPE NORMAL, DURATION 1.0")'
            tf.puts 'wait_check("INST HEALTH_STATUS COLLECTS == 1", 5)'
            tf.puts "end"
          end
          tf.puts "end"
          tf.close
          text = File.read(tf.path)
          count = 0
          start_time = Time.now
          @lex.each_lexed_segment(text) do |segment, instrumentable, inside_begin, line_no|
            count += 1
          end
          end_time = Time.now
          expect(count).to eql 1602
          expect(end_time - start_time).to be <= 1.0
        ensure
          tf.unlink
        end
      end
    end
  end
end
