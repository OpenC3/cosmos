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
require 'openc3'
require 'openc3/packets/packet_config'
require 'openc3/packets/parsers/packet_parser'
require 'tempfile'

module OpenC3
  describe PacketParser do
    describe "check_item_default_sizes" do
      # Only plugin install runs this check (TargetModel#deploy) so parsing
      # doesn't fail for targets installed before it was added
      def check(*lines)
        pc = PacketConfig.new
        tf = Tempfile.new('unittest')
        tf.puts 'COMMAND TGT1 PKT1 BIG_ENDIAN'
        lines.each { |line| tf.puts line }
        tf.close
        pc.process_file(tf.path, "TGT1")
        tf.unlink
        PacketParser.check_item_default_sizes(pc.commands["TGT1"]["PKT1"])
      end

      it "complains about STRING and BLOCK defaults that don't fit" do
        expect { check('  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"') }.to \
          raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default value of 8 bytes does not fit into 4 bytes for data_type STRING")
        expect { check('  APPEND_PARAMETER ITEM1 16 BLOCK 0x010203 "Description"') }.to \
          raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default value of 3 bytes does not fit into 2 bytes for data_type BLOCK")
        # DEFAULT_VALUE is applied before the check
        expect { check('  APPEND_PARAMETER ITEM1 32 STRING "OK" "Description"', '    DEFAULT_VALUE "TOO LONG"') }.to \
          raise_error(ArgumentError, /ITEM1: default value of 8 bytes/)
      end

      it "complains about REQUIRED parameter defaults that don't fit" do
        expect { check('  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"', '    REQUIRED') }.to \
          raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default value of 8 bytes does not fit into 4 bytes for data_type STRING")
      end

      it "allows defaults that fit, are truncated, or are variably sized" do
        expect {
          check('  APPEND_PARAMETER ITEM1 32 STRING "FITS" "Description"',
                '  APPEND_PARAMETER ITEM2 32 STRING "TRUNCATED" "Description"',
                '    OVERFLOW TRUNCATE',
                '  APPEND_PARAMETER ITEM3 0 STRING "ANY SIZE AT ALL" "Description"')
        }.to_not raise_error
      end

      it "checks the value of a default that names a state" do
        expect {
          check('  APPEND_PARAMETER ITEM1 8 STRING ENABLED "Description"',
                '    STATE ENABLED A',
                '    STATE DISABLED B')
        }.to_not raise_error
        expect {
          check('  APPEND_PARAMETER ITEM1 8 STRING ENABLED "Description"',
                '    STATE ENABLED TOOLONG')
        }.to raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default value of 7 bytes does not fit into 1 bytes for data_type STRING")
      end

      it "ignores non-binary accessors" do
        expect {
          check('  ACCESSOR JsonAccessor',
                '  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"',
                '    KEY $.item1')
        }.to_not raise_error
      end

      it "doesn't run when parsing so installed targets still load" do
        pc = PacketConfig.new
        tf = Tempfile.new('unittest')
        tf.puts 'COMMAND TGT1 PKT1 BIG_ENDIAN'
        tf.puts '  APPEND_PARAMETER ITEM1 32 STRING "TOO LONG" "Description"'
        tf.close
        expect { pc.process_file(tf.path, "TGT1") }.to_not raise_error
        tf.unlink
      end
    end

    describe "nil defaults" do
      before(:each) do
        @pc = PacketConfig.new
      end

      def process(*lines)
        tf = Tempfile.new('unittest')
        tf.puts 'COMMAND TGT1 PKT1 BIG_ENDIAN'
        lines.each { |line| tf.puts line }
        tf.close
        @pc.process_file(tf.path, "TGT1")
        @pc.commands["TGT1"]["PKT1"]
      ensure
        tf&.unlink
      end

      it "allows nil, none, or null defaults for REQUIRED parameters" do
        packet = process(
          '  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM2 16 INT MIN MAX None "INT"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM3 32 FLOAT MIN MAX NULL "FLOAT"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM4 32 STRING nil "STRING"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM5 32 BLOCK "none" "BLOCK"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM6 8 BOOL null "BOOL"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM7 64 ARRAY nil "ARRAY"', '    REQUIRED',
          '  APPEND_PARAMETER ITEM8 64 OBJECT nil "OBJECT"', '    REQUIRED',
          # DEFAULT_VALUE and REQUIRED can come in either order
          '  APPEND_PARAMETER ITEM9 16 UINT MIN MAX 0 "UINT"', '    REQUIRED', '    DEFAULT_VALUE nil'
        )
        (1..9).each { |i| expect(packet.get_item("ITEM#{i}").default).to be_nil }
      end

      it "complains about nil defaults for numeric parameters that aren't REQUIRED" do
        expect { process('  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"') }.to \
          raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default of nil is only allowed for REQUIRED parameters")
        @pc = PacketConfig.new
        expect { process('  APPEND_PARAMETER ITEM1 8 BOOL NONE "BOOL"') }.to \
          raise_error(ArgumentError, "TGT1 PKT1 ITEM1: default of NONE is only allowed for REQUIRED parameters")
      end

      it "keeps nil defaults for parameters with a write conversion or DERIVED" do
        # The write conversion or a DERIVED write handles the value
        packet = process('  APPEND_PARAMETER ITEM1 16 UINT MIN MAX NONE "UINT"',
                         '    POLY_WRITE_CONVERSION 0 1',
                         '  APPEND_PARAMETER ITEM2 0 DERIVED nil nil null "DERIVED"')
        expect(packet.get_item("ITEM1").default).to eql "NONE"
        expect(packet.get_item("ITEM2").default).to eql "null"
      end

      it "keeps nil defaults as strings for STRING and BLOCK parameters that aren't REQUIRED" do
        packet = process('  APPEND_PARAMETER ITEM1 32 STRING NONE "STRING"',
                         '  APPEND_PARAMETER ITEM2 32 BLOCK null "BLOCK"')
        expect(packet.get_item("ITEM1").default).to eql "NONE"
        expect(packet.get_item("ITEM2").default).to eql "null"
      end

      it "writes nil defaults to the config" do
        packet = process('  APPEND_PARAMETER ITEM1 16 UINT MIN MAX nil "UINT"', '    REQUIRED',
                         '  APPEND_PARAMETER ITEM2 32 STRING nil "STRING"', '    REQUIRED',
                         '  APPEND_PARAMETER ITEM3 8 BOOL nil "BOOL"', '    REQUIRED',
                         '  APPEND_PARAMETER ITEM4 64 ARRAY nil "ARRAY"', '    REQUIRED',
                         '  APPEND_PARAMETER ITEM5 64 OBJECT nil "OBJECT"', '    REQUIRED')
        config = packet.to_config(:COMMAND)
        expect(config).to include('PARAMETER ITEM1 0 16 UINT 0 65535 nil "UINT"')
        expect(config).to include('PARAMETER ITEM2 16 32 STRING nil "STRING"')
        # Only numeric types have a range
        expect(config).to include('PARAMETER ITEM3 48 8 BOOL nil "BOOL"')
        expect(config).to include('PARAMETER ITEM4 56 64 ARRAY nil "ARRAY"')
        expect(config).to include('PARAMETER ITEM5 120 64 OBJECT nil "OBJECT"')
        # The config loads back the same way
        @pc = PacketConfig.new
        packet = process(*config.split("\n").drop(1))
        (1..5).each { |i| expect(packet.get_item("ITEM#{i}").default).to be_nil }
      end
    end

    describe "process_file" do
      before(:each) do
        @pc = PacketConfig.new
      end

      it "complains if there are not enough parameters" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts(keyword)
          tf.close
          expect { @pc.process_file(tf.path, "SYSTEM") }.to raise_error(ConfigParser::Error, /Not enough parameters for #{keyword}/)
          tf.unlink
        end
      end

      it "complains if there are too many parameters" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts "#{keyword} tgt1 pkt1 LITTLE_ENDIAN 'Packet' extra"
          tf.close
          expect { @pc.process_file(tf.path, "TGT1") }.to raise_error(ConfigParser::Error, /Too many parameters for #{keyword}/)
          tf.unlink
        end
      end

      it "complains about invalid endianness" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts keyword + ' tgt1 pkt1 MIDDLE_ENDIAN "Packet"'
          tf.close
          expect { @pc.process_file(tf.path, "TGT1") }.to raise_error(ConfigParser::Error, /Invalid endianness MIDDLE_ENDIAN. Must be BIG_ENDIAN or LITTLE_ENDIAN./)
          tf.unlink
        end
      end

      it "processes target, packet, endianness, description" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts keyword + ' tgt1 pkt1 LITTLE_ENDIAN "Packet"'
          tf.close
          @pc.process_file(tf.path, "TGT1")
          pkt = @pc.commands["TGT1"]["PKT1"] if keyword == 'COMMAND'
          pkt = @pc.telemetry["TGT1"]["PKT1"] if keyword == 'TELEMETRY'
          expect(pkt.target_name).to eql "TGT1"
          expect(pkt.packet_name).to eql "PKT1"
          expect(pkt.default_endianness).to eql :LITTLE_ENDIAN
          expect(pkt.description).to eql "Packet"
          tf.unlink
        end
      end

      it "substitutes the target name" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts keyword + ' tgt1 pkt1 LITTLE_ENDIAN "Packet"'
          tf.close
          @pc.process_file(tf.path, "NEW")
          pkt = @pc.commands["NEW"]["PKT1"] if keyword == 'COMMAND'
          pkt = @pc.telemetry["NEW"]["PKT1"] if keyword == 'TELEMETRY'
          expect(pkt.target_name).to eql "NEW"
          tf.unlink
        end
      end

      it "complains if a packet is redefined" do
        %w(COMMAND TELEMETRY).each do |keyword|
          tf = Tempfile.new('unittest')
          tf.puts keyword + ' tgt1 pkt1 LITTLE_ENDIAN "Packet 1"'
          tf.puts keyword + ' tgt1 pkt1 LITTLE_ENDIAN "Packet 2"'
          tf.close
          @pc.process_file(tf.path, "SYSTEM")
          expect(@pc.warnings).to include("#{keyword.capitalize} Packet TGT1 PKT1 redefined.")
          tf.unlink
        end
      end
    end
  end
end
