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

require 'nokogiri'
require 'spec_helper'
require 'openc3'
require 'openc3/packets/packet_config'
require 'openc3/packets/parsers/xtce_converter'
require 'tempfile'
require 'equivalent-xml'

module OpenC3
  describe XtceConverter do
    before(:all) do
      setup_system()
    end

    describe "Convert CMD and TLM definitions" do
      before(:each) do
        @pc = PacketConfig.new
      end

      it "converts simple tlm/cmd and handles two ID_parameters with the same name" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  PARAMETER CMD_UNSIGNED 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"\
              "  PARAMETER CMD_SIGNED 32 16 INT -100 100 0 \"Signed\"\n"\
              "    UNITS Kilos K\n"\
              "  ARRAY_PARAMETER CMD_ARRAY 48 64 FLOAT 640 \"Array of 10 64bit floats\"\n"\
              "  PARAMETER CMD_FLOAT 688 32 FLOAT MIN MAX 10.0 \"Float\"\n"\
              "    POLY_WRITE_CONVERSION 10.0 0.5 0.25\n"\
              "  PARAMETER CMD_DOUBLE 720 64 FLOAT MIN MAX 0.0 \"Double\"\n"\
              "  PARAMETER CMD_STRING 784 32 STRING \"DEAD\" \"String\"\n"\
              "  PARAMETER CMD_STRING2 816 32 STRING 0xDEAD \"Binary\"\n"\
              "  PARAMETER CMD_BLOCK 848 32 BLOCK 0xBEEF \"Block\"\n"
        tf.puts cmd
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ID_ITEM OPCODE 0 8 UINT 1 \"Opcode\"\n"\
               "  ITEM UNSIGNED 8 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM SIGNED 16 8 INT \"Signed\"\n"\
               "    UNITS Kilos K\n"\
               "  ARRAY_ITEM ARRAY 24 8 UINT 80 \"Array\"\n"\
               "  ITEM FLOAT 104 32 FLOAT \"Float\"\n"\
               "    POLY_READ_CONVERSION 10.0 0.5 0.25\n"\
               "  ITEM DOUBLE 136 64 FLOAT \"Double\"\n"\
               "    LIMITS DEFAULT 1 ENABLED -80.0 -70.0 60.0 80.0\n"\
               "  ITEM STRING 200 32 STRING \"String\"\n"\
               "  ITEM BLOCK 232 32 BLOCK \"Block\"\n"\
               "  ITEM NOT_PACKED 300 8 UINT \"Not packed\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install)
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "simple_conversion.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
        expected_txt_path = File.join(File.dirname(__FILE__), "expected.xtce")
        result_txt_path = File.join(File.dirname(__FILE__), "result.xtce")
      end

      it "Substitutes '/' for '_' in names" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 SUBSYSTEM/CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD_OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"
        tf.puts cmd
        tlm1 = "TELEMETRY TGT1 SUBSYSTEM/TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ID_ITEM TLM_OPCODE 0 8 UINT 1 \"Opcode\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install)
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "substitution_1.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "Substitutes '.' for '_' in names" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD.OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  PARAMETER CMD.UNSIGNED 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"\
              "  PARAMETER CMD.SIGNED 32 16 INT -100 100 0 \"Signed\"\n"\
              "    UNITS Kilos K\n"\
              "  ARRAY_PARAMETER CMD.ARRAY 48 64 FLOAT 640 \"Array of 10 64bit floats\"\n"\
              "  PARAMETER CMD.FLOAT 688 32 FLOAT MIN MAX 10.0 \"Float\"\n"\
              "    POLY_WRITE_CONVERSION 10.0 0.5 0.25\n"\
              "  PARAMETER CMD.DOUBLE 720 64 FLOAT MIN MAX 0.0 \"Double\"\n"\
              "  PARAMETER CMD.STRING 784 32 STRING \"DEAD\" \"String\"\n"\
              "  PARAMETER CMD.STRING2 816 32 STRING 0xDEAD \"Binary\"\n"\
              "  PARAMETER CMD.BLOCK 848 32 BLOCK 0xBEEF \"Block\"\n"
        tf.puts cmd
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 1 \"Opcode\"\n"\
               "  ITEM TLM.UNSIGNED 8 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM TLM.SIGNED 16 8 INT \"Signed\"\n"\
               "    UNITS Kilos K\n"\
               "  ARRAY_ITEM TLM.ARRAY 24 8 UINT 80 \"Array\"\n"\
               "  ITEM TLM.FLOAT 104 32 FLOAT \"Float\"\n"\
               "    POLY_READ_CONVERSION 10.0 0.5 0.25\n"\
               "  ITEM TLM.DOUBLE 136 64 FLOAT \"Double\"\n"\
               "    LIMITS DEFAULT 1 ENABLED -80.0 -70.0 60.0 80.0\n"\
               "  ITEM TLM.STRING 200 32 STRING \"String\"\n"\
               "  ITEM TLM.BLOCK 232 32 BLOCK \"Block\"\n"\
               "  ITEM TLM.NOT_PACKED 300 8 UINT \"Not packed\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install)
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "substitution_2.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "Substitutes '[]' for '_' in names" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD_OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  PARAMETER UNSIGNED[0] 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"\
              "  PARAMETER UNSIGNED[1] 32 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"\
              "  PARAMETER UNSIGNED[2] 48 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf.puts cmd
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ID_ITEM TLM_OPCODE 0 8 UINT 1 \"Opcode\"\n"\
               "  ITEM UNSIGNED[0] 8 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM UNSIGNED[1] 16 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM UNSIGNED[2] 24 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install)
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "substitution_3.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "adds AncillaryData for ALLOW_SHORT TLM packets" do
        tf = Tempfile.new('unittest')
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ALLOW_SHORT \n"\
               "  ID_ITEM TLM_OPCODE 0 8 UINT 1 \"Opcode\"\n"\
               "  ITEM UNSIGNED[0] 8 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM UNSIGNED[1] 16 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM UNSIGNED[2] 24 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install)
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "allow_short_test.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      #TODO:
      #it "creates a template for derived parameters" do
      #  tf = Tempfile.new('unittest')
      #  tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
      #         "  ALLOW_SHORT \n"\
      #         "  ID_ITEM TLM_OPCODE 0 8 UINT 1 \"Opcode\"\n"\
      #         "  ITEM UNSIGNED[0] 8 8 UINT \"Unsigned\"\n"\
      #         "    STATE FALSE 0\n"\
      #         "    STATE TRUE 1\n"\
      #         "  ITEM UNSIGNED[1] 16 8 UINT \"Unsigned\"\n"\
      #         "    STATE FALSE 0\n"\
      #         "    STATE TRUE 1\n"\
      #         "  ITEM UNSIGNED[2] 24 8 UINT \"Unsigned\"\n"\
      #         "    STATE FALSE 0\n"\
      #         "    STATE TRUE 1\n"
      #  tf.puts tlm1
      #  tf.close
      #  @pc.process_file(tf.path, "TGT1")
      #  spec_install = File.join("..", "..", "install")
      #  @pc.to_xtce(spec_install)
      #  xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
      #  expect(File.exist?(xml_path)).to be true
      #  xtce_doc = Nokogiri::XML(File.open(xml_path))
      #  expected_output_file_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "allow_short_test.xtce")
      #  expected_result_xml = Nokogiri::XML(File.open(expected_output_file_path))
      #  expect(xtce_doc).to be_equivalent_to(expected_result_xml)
      #  tf.unlink
      #  FileUtils.rm_rf File.join(spec_install, "TGT1")
      #end

      it "combines two XTCE files for two targets into one file" do
        combination_dir = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combine_targets")
        combination_result_dir = File.join( combination_dir, "TARGETS_COMBINED")
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        result_xml = Nokogiri::XML(File.open(output_path))
        expected_result_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combined_targets_test.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_result_path))
        expect(result_xml).to be_equivalent_to(expected_result_xml)
        FileUtils.rm_rf combination_result_dir 
      end

      it "combines two XTCE files for two targets into one file with TGT1 as root" do
        combination_dir = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combine_targets")
        combination_result_dir = File.join( combination_dir, "TARGETS_COMBINED")
        output_path = XtceConverter.combine_output_xtce(combination_dir, root_target_name="TGT1")
        result_xml = Nokogiri::XML(File.open(output_path))
        expected_result_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combined_targets_test_with_TGT1_as_root.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_result_path))
        expect(result_xml).to be_equivalent_to(expected_result_xml)
        FileUtils.rm_rf combination_result_dir 
      end

      it "combines two XTCE files for two targets into one file with TGT2 as root" do
        combination_dir = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combine_targets")
        combination_result_dir = File.join( combination_dir, "TARGETS_COMBINED")
        output_path = XtceConverter.combine_output_xtce(combination_dir, root_target_name="TGT2")
        result_xml = Nokogiri::XML(File.open(output_path))
        expected_result_path = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combined_targets_test_with_TGT2_as_root.xtce")
        expected_result_xml = Nokogiri::XML(File.open(expected_result_path))
        expect(result_xml).to be_equivalent_to(expected_result_xml)
        FileUtils.rm_rf combination_result_dir 
      end

      it "doesnt perfom combination where only one xtce file exists" do
        combination_dir = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combine_targets", "target_1")
        combination_result_dir = File.join(combination_dir, "TARGETS_COMBINED")
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        expect(output_path).to be nil
        expect(File.directory?(combination_result_dir)).to be false
      end

      it "doesnt perfom combination where no xtce file exists" do
        combination_dir = File.join(File.dirname(__FILE__),"expected_xtce_outputs", "combine_targets", "empty_folder")
        combination_result_dir = File.join(combination_dir, "TARGETS_COMBINED")
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        expect(output_path).to be nil
        expect(File.directory?(combination_result_dir)).to be false
      end
    end
  end
end

# TODO: remove later
        #File.open(result_txt_path, "w") do |file|
        #  file.puts xtce_doc.to_xml
        #end
        #File.open(expected_txt_path, "w") do |file|
        #  file.puts expected_result_xml.to_xml
        #end
