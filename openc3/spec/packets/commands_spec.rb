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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/packets/commands'
require 'tempfile'

module OpenC3
  describe Commands do
    describe "initialize" do
      it "has no warnings" do
        expect(Commands.new(PacketConfig.new).warnings).to be_empty
      end
    end

    before(:all) do
      setup_system()
    end

    before(:each) do
      tf = Tempfile.new('unittest')
      tf.puts '# This is a comment'
      tf.puts '#'
      tf.puts 'COMMAND tgt1 pkt1 LITTLE_ENDIAN "TGT1 PKT1 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 8 UINT 1 1 1 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 8 UINT 0 200 2 "Item2"'
      tf.puts '  APPEND_PARAMETER item3 8 UINT 0 200 3 "Item3"'
      tf.puts '  APPEND_PARAMETER item4 8 UINT 0 200 4 "Item4"'
      tf.puts 'COMMAND tgt1 pkt2 LITTLE_ENDIAN "TGT1 PKT2 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 8 UINT 2 2 2 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 8 UINT 0 255 2 "Item2"'
      tf.puts '    STATE BAD1 0 HAZARDOUS "Hazardous"'
      tf.puts '    STATE BAD2 1 HAZARDOUS'
      tf.puts '    STATE GOOD 2 DISABLE_MESSAGES'
      tf.puts '  APPEND_PARAMETER item3 32 FLOAT 0 1 0 "Item3"'
      tf.puts '    STATE S1 0.0'
      tf.puts '    STATE S2 0.25'
      tf.puts '    STATE S3 0.5'
      tf.puts '    STATE S4 0.75'
      tf.puts '    STATE S5 1.0'
      tf.puts '  APPEND_PARAMETER item4 40 STRING "HELLO"'
      tf.puts '    STATE HI HELLO'
      tf.puts '    STATE WO WORLD'
      tf.puts '    STATE JA JASON'
      tf.puts 'COMMAND tgt2 pkt3 LITTLE_ENDIAN "TGT2 PKT3 Description"'
      tf.puts '  HAZARDOUS "Hazardous"'
      tf.puts '  APPEND_ID_PARAMETER item1 8 UINT 3 3 3 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 8 UINT 0 255 2 "Item2"'
      tf.puts '    REQUIRED'
      tf.puts 'COMMAND tgt2 pkt4 LITTLE_ENDIAN "TGT2 PKT4 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 8 UINT 4 4 4 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 2048 STRING "Item2"'
      tf.puts '    OVERFLOW TRUNCATE'
      tf.puts 'COMMAND tgt2 pkt5 LITTLE_ENDIAN "TGT2 PKT5 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 8 UINT 5 5 5 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 8 UINT 0 100 0 "Item2"'
      tf.puts '    POLY_WRITE_CONVERSION 0 2'
      tf.puts 'COMMAND tgt2 pkt6 BIG_ENDIAN "TGT2 PKT6 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 16 UINT 6 6 6 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 16 UINT MIN MAX 0 "Item2" LITTLE_ENDIAN'
      tf.puts '  APPEND_PARAMETER item3 16 UINT MIN MAX 0 "Item3"'
      tf.puts 'COMMAND tgt2 pkt7 BIG_ENDIAN "TGT2 PKT7 Description"'
      tf.puts '  APPEND_ID_PARAMETER item1 16 UINT 6 6 6 "Item1"'
      tf.puts '  APPEND_PARAMETER item2 16 UINT MIN MAX 0 "Item2" LITTLE_ENDIAN'
      tf.puts '  APPEND_PARAMETER item3 16 UINT MIN MAX 0 "Item3"'
      tf.puts '    OBFUSCATE'
      tf.close

      pc = PacketConfig.new
      pc.process_file(tf.path, "SYSTEM")
      @cmd = Commands.new(pc)
      tf.unlink
    end

    describe "target_names" do
      it "returns an empty array if no targets" do
        expect(Commands.new(PacketConfig.new).target_names).to eql []
      end

      it "returns all target names" do
        expect(@cmd.target_names).to eql ["TGT1", "TGT2"]
      end
    end

    describe "packets" do
      it "complains about non-existent targets" do
        expect { @cmd.packets("tgtX") }.to raise_error(RuntimeError, "Command target 'TGTX' does not exist")
      end

      it "returns all packets target TGT1" do
        pkts = @cmd.packets("TGT1")
        expect(pkts.length).to eql 2
        expect(pkts.keys).to include("PKT1")
        expect(pkts.keys).to include("PKT2")
      end

      it "returns all packets target TGT2" do
        pkts = @cmd.packets("TGT2")
        expect(pkts.length).to eql 5
        expect(pkts.keys).to include("PKT3")
        expect(pkts.keys).to include("PKT4")
        expect(pkts.keys).to include("PKT5")
        expect(pkts.keys).to include("PKT6")
        expect(pkts.keys).to include("PKT7")
      end
    end

    describe "params" do
      it "complains about non-existent targets" do
        expect { @cmd.params("TGTX", "PKT1") }.to raise_error(RuntimeError, "Command target 'TGTX' does not exist")
      end

      it "complains about non-existent packets" do
        expect { @cmd.params("TGT1", "PKTX") }.to raise_error(RuntimeError, "Command packet 'TGT1 PKTX' does not exist")
      end

      it "returns all items from packet TGT1/PKT1" do
        items = @cmd.params("TGT1", "PKT1")
        expect(items.length).to eql 9
        Packet::RESERVED_ITEM_NAMES.each do |reserved|
          expect(items.map { |item| item.name }).to include(reserved)
        end
        expect(items[5].name).to eql "ITEM1"
        expect(items[6].name).to eql "ITEM2"
        expect(items[7].name).to eql "ITEM3"
        expect(items[8].name).to eql "ITEM4"
      end
    end

    describe "packet" do
      it "complains about non-existent targets" do
        expect { @cmd.packet("tgtX", "pkt1") }.to raise_error(RuntimeError, "Command target 'TGTX' does not exist")
      end

      it "complains about non-existent packets" do
        expect { @cmd.packet("TGT1", "PKTX") }.to raise_error(RuntimeError, "Command packet 'TGT1 PKTX' does not exist")
      end

      it "returns the specified packet" do
        pkt = @cmd.packet("TGT1", "PKT1")
        expect(pkt.target_name).to eql "TGT1"
        expect(pkt.packet_name).to eql "PKT1"
      end
    end

    describe "identify" do
      it "return nil with a nil buffer" do
        expect(@cmd.identify(nil)).to be_nil
      end

      it "only checks the targets given" do
        buffer = "\x01\x02\x03\x04"
        pkt = @cmd.identify(buffer, ["TGT1"])
        pkt.enable_method_missing
        expect(pkt.item1).to eql 1
        expect(pkt.item2).to eql 2
        expect(pkt.item3).to eql 3
        expect(pkt.item4).to eql 4
      end

      it "works in unique id mode or not" do
        System.targets["TGT1"] = Target.new("TGT1", Dir.pwd)
        target = System.targets["TGT1"]
        target.cmd_unique_id_mode = false
        buffer = "\x01\x02\x03\x04"
        pkt = @cmd.identify(buffer, ["TGT1"])
        pkt.enable_method_missing
        expect(pkt.item1).to eql 1
        expect(pkt.item2).to eql 2
        expect(pkt.item3).to eql 3
        expect(pkt.item4).to eql 4
        target.cmd_unique_id_mode = true
        buffer = "\x01\x02\x01\x02"
        pkt = @cmd.identify(buffer, ["TGT1"])
        pkt.enable_method_missing
        expect(pkt.item1).to eql 1
        expect(pkt.item2).to eql 2
        expect(pkt.item3).to eql 1
        expect(pkt.item4).to eql 2
        target.cmd_unique_id_mode = false
      end

      it "returns nil with unknown targets given" do
        buffer = "\x01\x02\x03\x04"
        expect(@cmd.identify(buffer, ["TGTX"])).to be_nil
      end

      context "with an unknown buffer" do
        it "logs an invalid sized buffer" do
          capture_io do |stdout|
            buffer = "\x01\x02\x03"
            pkt = @cmd.identify(buffer)
            pkt.enable_method_missing
            expect(pkt.item1).to eql 1
            expect(pkt.item2).to eql 2
            expect(pkt.item3).to eql 3
            expect(pkt.item4).to eql 0
            expect(stdout.string).to match(/TGT1 PKT1 received with actual packet length of 3 but defined length of 4/)
          end
        end

        it "logs an invalid sized buffer" do
          capture_io do |stdout|
            buffer = "\x01\x02\x03\x04\x05"
            pkt = @cmd.identify(buffer)
            pkt.enable_method_missing
            expect(pkt.item1).to eql 1
            expect(pkt.item2).to eql 2
            expect(pkt.item3).to eql 3
            expect(pkt.item4).to eql 4
            expect(stdout.string).to match(/TGT1 PKT1 received with actual packet length of 5 but defined length of 4/)
          end
        end

        it "identifies TGT1 PKT1 but not affect the latest data table" do
          buffer = "\x01\x02\x03\x04"
          pkt = @cmd.identify(buffer)
          pkt.enable_method_missing
          expect(pkt.item1).to eql 1
          expect(pkt.item2).to eql 2
          expect(pkt.item3).to eql 3
          expect(pkt.item4).to eql 4

          # Now request the packet from the latest data table
          pkt = @cmd.packet("TGT1", "PKT1")
          pkt.enable_method_missing
          expect(pkt.item1).to eql 0
          expect(pkt.item2).to eql 0
          expect(pkt.item3).to eql 0
          expect(pkt.item4).to eql 0
        end

        it "identifies TGT1 PKT2" do
          buffer = "\x02\x02"
          pkt = @cmd.identify(buffer)
          pkt.enable_method_missing
          expect(pkt.item1).to eql 2
          expect(pkt.item2).to eql "GOOD"
        end

        it "identifies TGT2 PKT1" do
          buffer = "\x03\x02"
          pkt = @cmd.identify(buffer)
          pkt.enable_method_missing
          expect(pkt.item1).to eql 3
          expect(pkt.item2).to eql 2
        end
      end
    end

    describe "build_cmd" do
      # Test all the combinations of range_checking and raw
      [true, false].each do |range_checking|
        [true, false].each do |raw|
          it "complains about non-existent targets" do
            expect { @cmd.build_cmd("tgtX", "pkt1", range_checking, raw) }.to raise_error(RuntimeError, "Command target 'TGTX' does not exist")
          end

          it "complains about non-existent packets" do
            expect { @cmd.build_cmd("tgt1", "pktX", range_checking, raw) }.to raise_error(RuntimeError, "Command packet 'TGT1 PKTX' does not exist")
          end

          it "complains about non-existent items" do
            expect { @cmd.build_cmd("tgt1", "pkt1", { "itemX" => 1 }, range_checking, raw) }.to raise_error(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist")
          end

          it "complains about missing required parameters" do
            expect { @cmd.build_cmd("tgt2", "pkt3", {}, range_checking, raw) }.to raise_error(RuntimeError, "Required command parameter 'TGT2 PKT3 ITEM2' not given")
          end

          it "creates a command packet with mixed endianness" do
            items = { "ITEM2" => 0xABCD, "ITEM3" => 0x6789 }
            cmd = @cmd.build_cmd("TGT2", "PKT6", items, range_checking, raw)
            cmd.enable_method_missing
            expect(cmd.item1).to eql 6
            expect(cmd.item2).to eql 0xABCD
            expect(cmd.item3).to eql 0x6789
            expect(cmd.buffer).to eql "\x00\x06\xCD\xAB\x67\x89"
          end

          it "resets the buffer size" do
            packet = @cmd.packet('TGT1', 'PKT1')
            packet.buffer = "\x00" * (packet.defined_length + 1)
            expect(packet.length).to eql 5
            items = { "ITEM2" => 10 }
            cmd = @cmd.build_cmd("TGT1", "PKT1", items, range_checking, raw)
            expect(cmd.read("ITEM2")).to eql 10
            expect(cmd.length).to eql 4
          end

          it "creates a populated command packet with default values" do
            cmd = @cmd.build_cmd("TGT1", "PKT1", {}, range_checking, raw)
            cmd.enable_method_missing
            expect(cmd.raw).to eql raw
            expect(cmd.item1).to eql 1
            expect(cmd.item2).to eql 2
            expect(cmd.item3).to eql 3
            expect(cmd.item4).to eql 4
          end

          it "creates a command packet with override item values" do
            items = { "ITEM2" => 10, "ITEM4" => 11 }
            cmd = @cmd.build_cmd("TGT1", "PKT1", items, range_checking, raw)
            cmd.enable_method_missing
            expect(cmd.raw).to eql raw
            expect(cmd.item1).to eql 1
            expect(cmd.item2).to eql 10
            expect(cmd.item3).to eql 3
            expect(cmd.item4).to eql 11
          end

          it "creates a command packet with override item value states" do
            if raw
              items = { "ITEM2" => 2, "ITEM3" => 0.5, "ITEM4" => "WORLD" }
            else
              # Converted (not raw) can take either states or values
              items = { "ITEM2" => 2, "ITEM3" => "S3", "ITEM4" => "WO" }
            end
            cmd = @cmd.build_cmd("TGT1", "PKT2", items, range_checking, raw)
            cmd.enable_method_missing
            expect(cmd.item1).to eql 2
            expect(cmd.item2).to eql "GOOD"
            expect(cmd.read("ITEM2", :RAW)).to eql 2
            expect(cmd.item3).to eql "S3"
            expect(cmd.read("ITEM3", :RAW)).to eql 0.5
            expect(cmd.item4).to eql "WO"
            expect(cmd.read("ITEM4", :RAW)).to eql 'WORLD'
          end

          if range_checking
            it "complains about out of range item values" do
              expect { @cmd.build_cmd("tgt1", "pkt1", { "item2" => 255 }, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT1 ITEM2' = 255 not in valid range of 0 to 200")
            end

            it "complains about out of range item states" do
              items = { "ITEM2" => 3, "ITEM3" => 0.0, "ITEM4" => "WORLD" }
              if raw
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM2' = 3 not one of 0, 1, 2")
              else
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM2' = 3 not one of BAD1, BAD2, GOOD")
              end

              items = { "ITEM2" => 0, "ITEM3" => 2.0, "ITEM4" => "WORLD" }
              if raw
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM3' = 2.0 not one of 0.0, 0.25, 0.5, 0.75, 1.0")
              else
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM3' = 2.0 not one of S1, S2, S3, S4, S5")
              end

              items = { "ITEM2" => 0, "ITEM3" => 0.0, "ITEM4" => "TESTY" }
              if raw
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM4' = TESTY not one of HELLO, WORLD, JASON")
              else
                expect { @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw) }.to raise_error(RuntimeError, "Command parameter 'TGT1 PKT2 ITEM4' = TESTY not one of HI, WO, JA")
              end
            end
          else
            it "ignores out of range item values if requested" do
              cmd = @cmd.build_cmd("tgt1", "pkt1", { "item2" => 255 }, range_checking, raw)
              cmd.enable_method_missing
              expect(cmd.item1).to eql 1
              expect(cmd.item2).to eql 255
              expect(cmd.item3).to eql 3
              expect(cmd.item4).to eql 4
            end

            it "ignores out of range item states if requested" do
              items = { "ITEM2" => 3, "ITEM3" => 0.0, "ITEM4" => "WORLD" }
              cmd = @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw)
              expect(cmd.read("ITEM2", :RAW)).to eql 3
              expect(cmd.read("ITEM3", :RAW)).to eql 0.0
              expect(cmd.read("ITEM4", :RAW)).to eql 'WORLD'

              items = { "ITEM2" => 0, "ITEM3" => 2.0, "ITEM4" => "WORLD" }
              cmd = @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw)
              expect(cmd.read("ITEM2", :RAW)).to eql 0
              expect(cmd.read("ITEM3", :RAW)).to eql 2.0
              expect(cmd.read("ITEM4", :RAW)).to eql 'WORLD'

              items = { "ITEM2" => 0, "ITEM3" => 0.0, "ITEM4" => "TESTY" }
              cmd = @cmd.build_cmd("tgt1", "pkt2", items, range_checking, raw)
              expect(cmd.read("ITEM2", :RAW)).to eql 0
              expect(cmd.read("ITEM3", :RAW)).to eql 0.0
              expect(cmd.read("ITEM4", :RAW)).to eql 'TESTY'
            end
          end
        end
      end
    end

    describe "format" do
      it "creates a string representation of a command" do
        pkt = @cmd.packet("TGT1", "PKT1")
        expect(@cmd.format(pkt)).to eql "cmd(\"TGT1 PKT1 with ITEM1 0, ITEM2 0, ITEM3 0, ITEM4 0\")"

        pkt = @cmd.packet("TGT2", "PKT4")
        string = ''
        pkt.write("ITEM2", "HELLO WORLD")
        expect(@cmd.format(pkt)).to eql "cmd(\"TGT2 PKT4 with ITEM1 0, ITEM2 'HELLO WORLD'\")"

        pkt = @cmd.packet("TGT2", "PKT4")
        string = ''
        pkt.write("ITEM2", "HELLO WORLD")
        pkt.raw = true
        expect(@cmd.format(pkt)).to eql "cmd_raw(\"TGT2 PKT4 with ITEM1 0, ITEM2 'HELLO WORLD'\")"

        # If the string is too big it should truncate it
        (1..2028).each { |_i| string << 'A' }
        pkt.write("ITEM2", string)
        pkt.raw = false
        result = @cmd.format(pkt)
        expect(result).to match(/cmd\("TGT2 PKT4 with ITEM1 0, ITEM2 'AAAAAAAAAAA/)
        expect(result).to match(/AAAAAAAAAAA.../)
      end

      it "ignores parameters" do
        pkt = @cmd.packet("TGT1", "PKT1")
        expect(@cmd.format(pkt, ['ITEM3', 'ITEM4'])).to eql "cmd(\"TGT1 PKT1 with ITEM1 0, ITEM2 0\")"
      end

      it "handles obfuscated items" do
        pkt = @cmd.packet("TGT2", "PKT7")
        expect(@cmd.format(pkt, [])).to eql "cmd(\"TGT2 PKT7 with ITEM1 0, ITEM2 0, ITEM3 *****\")"
      end
    end

    describe "cmd_hazardous?" do
      it "complains about non-existent targets" do
        expect { @cmd.cmd_hazardous?("tgtX", "pkt1") }.to raise_error(RuntimeError, "Command target 'TGTX' does not exist")
      end

      it "complains about non-existent packets" do
        expect { @cmd.cmd_hazardous?("tgt1", "pktX") }.to raise_error(RuntimeError, "Command packet 'TGT1 PKTX' does not exist")
      end

      it "complains about non-existent items" do
        expect { @cmd.cmd_hazardous?("tgt1", "pkt1", { "itemX" => 1 }) }.to raise_error(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist")
      end

      it "returns true if the command overall is hazardous" do
        hazardous, description = @cmd.cmd_hazardous?("TGT1", "PKT1")
        expect(hazardous).to be false
        expect(description).to be_nil
        hazardous, description = @cmd.cmd_hazardous?("tgt2", "pkt3")
        expect(hazardous).to be true
        expect(description).to eql "Hazardous"
      end

      it "returns true if a command parameter is hazardous" do
        hazardous, description = @cmd.cmd_hazardous?("TGT1", "PKT2", { "ITEM2" => 0 })
        expect(hazardous).to be true
        expect(description).to eql "Hazardous"
        hazardous, description = @cmd.cmd_hazardous?("TGT1", "PKT2", { "ITEM2" => 1 })
        expect(hazardous).to be true
        expect(description).to eql ""
        hazardous, description = @cmd.cmd_hazardous?("TGT1", "PKT2", { "ITEM2" => 2 })
        expect(hazardous).to be false
        expect(description).to be_nil
      end
    end

    describe "all" do
      it "returns all packets" do
        expect(@cmd.all.keys).to eql %w(UNKNOWN TGT1 TGT2)
      end
    end
  end
end
