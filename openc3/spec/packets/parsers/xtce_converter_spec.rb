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

    def xml_file(target)
      tf = Tempfile.new(["unittest", ".xtce"])
      tf.puts '<?xml version="1.0" encoding="UTF-8"?>'
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"#{target}\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      yield tf
      tf.puts '</xtce:SpaceSystem>'
      tf.close
      tf
    end

    def telemetry_file(target)
      file = xml_file(target) do |tf|
        tf.puts '  <xtce:TelemetryMetaData>'
        yield tf
        tf.puts '  </xtce:TelemetryMetaData>'
      end
      file
    end

    def command_file(target)
      file = xml_file(target) do |tf|
        tf.puts '  <xtce:CommandMetaData>'
        yield tf
        tf.puts '  </xtce:CommandMetaData>'
      end
      file
    end

    def sample_simple_tlm_packet_with_alias(tf, with_allow_short: false)
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "      <xtce:IntegerParameterType name=\"TLM_OPCODE_Type\" shortDescription=\"TLM_OPCODE Description\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "    </xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "      <xtce:Parameter name=\"TLM_OPCODE\" parameterTypeRef=\"TLM_OPCODE_Type\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"TLM.OPCODE\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "      </xtce:Parameter>"
      tf.puts "    </xtce:ParameterSet>"
      tf.puts "    <xtce:ContainerSet>"
      # A packet with ID items inherits from an abstract container holding the entries
      # so the ID comparisons have a BaseContainer to live on
      tf.puts "      <xtce:SequenceContainer name=\"TLMPKT_Base\" abstract=\"true\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"TLM_OPCODE\"/>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "      <xtce:SequenceContainer name=\"TLMPKT\" shortDescription=\"TLMPKT Description\">"
      if with_allow_short
        tf.puts "        <xtce:AncillaryDataSet>"
        tf.puts "          <xtce:AncillaryData name=\"ALLOW_SHORT\">true</xtce:AncillaryData>"
        tf.puts "        </xtce:AncillaryDataSet>"
      end
      tf.puts "        <xtce:EntryList/>"
      tf.puts "        <xtce:BaseContainer containerRef=\"TLMPKT_Base\">"
      tf.puts "          <xtce:RestrictionCriteria>"
      tf.puts "            <xtce:ComparisonList>"
      tf.puts "              <xtce:Comparison parameterRef=\"TLM_OPCODE\" value=\"0\"/>"
      tf.puts "            </xtce:ComparisonList>"
      tf.puts "          </xtce:RestrictionCriteria>"
      tf.puts "        </xtce:BaseContainer>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "    </xtce:ContainerSet>"
      tf
    end

    def sample_simple_cmd_packet_with_alias(tf)
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "      <xtce:IntegerParameterType name=\"CMD_0__ATTRIBUTES_ID_Type\" initialValue=\"0\" shortDescription=\"CMD_ID Description\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"unsigned\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:ValidRange minInclusive=\"0\" maxInclusive=\"0\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "    </xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "      <xtce:Parameter name=\"CMD_0__ATTRIBUTES_ID\" parameterTypeRef=\"CMD_0__ATTRIBUTES_ID_Type\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"CMD[0].ATTRIBUTES/ID\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "      </xtce:Parameter>"
      tf.puts "    </xtce:ParameterSet>"
      tf.puts "    <xtce:ArgumentTypeSet>"
      tf.puts "      <xtce:EnumeratedArgumentType name=\"CMDPKT_CMD_0__ATTRIBUTES_BOOL_Type\" initialValue=\"TRUE\" shortDescription=\"Unsigned\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"unsigned\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:EnumerationList>"
      tf.puts "          <xtce:Enumeration value=\"0\" label=\"FALSE\"/>"
      tf.puts "          <xtce:Enumeration value=\"1\" label=\"TRUE\"/>"
      tf.puts "        </xtce:EnumerationList>"
      tf.puts "      </xtce:EnumeratedArgumentType>"
      tf.puts "    </xtce:ArgumentTypeSet>"
      tf.puts "    <xtce:MetaCommandSet>"
      # A command with ID items inherits from an abstract MetaCommand holding the
      # arguments and entries so the ID comparisons have a BaseContainer to live on
      tf.puts "      <xtce:MetaCommand name=\"CMDPKT_Base\" abstract=\"true\">"
      tf.puts "        <xtce:ArgumentList>"
      tf.puts "          <xtce:Argument name=\"CMD_0__ATTRIBUTES_BOOL\" argumentTypeRef=\"CMDPKT_CMD_0__ATTRIBUTES_BOOL_Type\" initialValue=\"TRUE\">"
      tf.puts "            <xtce:AliasSet>"
      tf.puts "              <xtce:Alias nameSpace=\"COSMOS\" alias=\"CMD[0].ATTRIBUTES/BOOL\"/>"
      tf.puts "            </xtce:AliasSet>"
      tf.puts "          </xtce:Argument>"
      tf.puts "        </xtce:ArgumentList>"
      tf.puts "        <xtce:CommandContainer name=\"CMDPKT_CommandsBase\">"
      tf.puts "          <xtce:EntryList>"
      tf.puts "            <xtce:ParameterRefEntry parameterRef=\"CMD_0__ATTRIBUTES_ID\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_0__ATTRIBUTES_BOOL\"/>"
      tf.puts "          </xtce:EntryList>"
      tf.puts "        </xtce:CommandContainer>"
      tf.puts "      </xtce:MetaCommand>"
      tf.puts "      <xtce:MetaCommand name=\"CMDPKT\" shortDescription=\"Command\">"
      tf.puts "        <xtce:BaseMetaCommand metaCommandRef=\"CMDPKT_Base\"/>"
      tf.puts "        <xtce:CommandContainer name=\"CMDPKT_Commands\">"
      tf.puts "          <xtce:EntryList/>"
      tf.puts "          <xtce:BaseContainer containerRef=\"CMDPKT_CommandsBase\">"
      tf.puts "            <xtce:RestrictionCriteria>"
      tf.puts "              <xtce:ComparisonList>"
      tf.puts "                <xtce:Comparison parameterRef=\"CMD_0__ATTRIBUTES_ID\" value=\"0\"/>"
      tf.puts "              </xtce:ComparisonList>"
      tf.puts "            </xtce:RestrictionCriteria>"
      tf.puts "          </xtce:BaseContainer>"
      tf.puts "        </xtce:CommandContainer>"
      tf.puts "      </xtce:MetaCommand>"
      tf.puts "    </xtce:MetaCommandSet>"
      tf
    end

    def sample_tlm_with_dynamic_string(tf)
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "      <xtce:IntegerParameterType name=\"OPCODE_Type\" shortDescription=\"OPCODE Description\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "      <xtce:StringParameterType name=\"DYNAMIC_Type\" characterWidth=\"8\" shortDescription=\"DYNAMIC Description\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:StringDataEncoding encoding=\"UTF-8\">"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:Fixed>"
      tf.puts "              <xtce:FixedValue>2048</xtce:FixedValue>"
      tf.puts "            </xtce:Fixed>"
      tf.puts "            <xtce:TerminationChar>00</xtce:TerminationChar>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:StringDataEncoding>"
      tf.puts "      </xtce:StringParameterType>"
      tf.puts "    </xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "      <xtce:Parameter name=\"OPCODE\" parameterTypeRef=\"OPCODE_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"DYNAMIC\" parameterTypeRef=\"DYNAMIC_Type\"/>"
      tf.puts "    </xtce:ParameterSet>"
      tf.puts "    <xtce:ContainerSet>"
      tf.puts "      <xtce:SequenceContainer name=\"TLMPKT_Base\" abstract=\"true\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"OPCODE\"/>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"DYNAMIC\"/>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "      <xtce:SequenceContainer name=\"TLMPKT\" shortDescription=\"TLMPKT Description\">"
      tf.puts "        <xtce:EntryList/>"
      tf.puts "        <xtce:BaseContainer containerRef=\"TLMPKT_Base\">"
      tf.puts "          <xtce:RestrictionCriteria>"
      tf.puts "            <xtce:ComparisonList>"
      tf.puts "              <xtce:Comparison parameterRef=\"OPCODE\" value=\"0\"/>"
      tf.puts "            </xtce:ComparisonList>"
      tf.puts "          </xtce:RestrictionCriteria>"
      tf.puts "        </xtce:BaseContainer>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "    </xtce:ContainerSet>"
      tf
    end

    def no_root_specified(target_1, target_2)
      tf = Tempfile.new(["unittest", ".xtce"])
      tf.puts '<?xml version="1.0" encoding="UTF-8"?>'
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"root\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      tf.puts "  <xtce:SpaceSystem name=\"#{target_1}\">"
      tf.puts '  <xtce:TelemetryMetaData>'
      sample_simple_tlm_packet_with_alias(tf)
      tf.puts '  </xtce:TelemetryMetaData>'
      tf.puts '  <xtce:CommandMetaData>'
      sample_simple_cmd_packet_with_alias(tf)
      tf.puts '  </xtce:CommandMetaData>'
      tf.puts '</xtce:SpaceSystem>'
      tf.puts "  <xtce:SpaceSystem name=\"#{target_2}\">"
      tf.puts '  <xtce:TelemetryMetaData>'
      sample_simple_tlm_packet_with_alias(tf)
      tf.puts '  </xtce:TelemetryMetaData>'
      tf.puts '  <xtce:CommandMetaData>'
      sample_simple_cmd_packet_with_alias(tf)
      tf.puts '  </xtce:CommandMetaData>'
      tf.puts '</xtce:SpaceSystem>'
      tf.puts '</xtce:SpaceSystem>'
      tf.close
      tf
    end

    def root_specified(root, non_root)
      tf = Tempfile.new(["unittest", ".xtce"])
      tf.puts '<?xml version="1.0" encoding="UTF-8"?>'
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"#{root}\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      tf.puts '  <xtce:TelemetryMetaData>'
      sample_simple_tlm_packet_with_alias(tf)
      tf.puts '  </xtce:TelemetryMetaData>'
      tf.puts '  <xtce:CommandMetaData>'
      sample_simple_cmd_packet_with_alias(tf)
      tf.puts '  </xtce:CommandMetaData>'
      tf.puts "<xtce:SpaceSystem name=\"#{non_root}\">"
      tf.puts '  <xtce:TelemetryMetaData>'
      sample_simple_tlm_packet_with_alias(tf)
      tf.puts '  </xtce:TelemetryMetaData>'
      tf.puts '  <xtce:CommandMetaData>'
      sample_simple_cmd_packet_with_alias(tf)
      tf.puts '  </xtce:CommandMetaData>'
      tf.puts '</xtce:SpaceSystem>'
      tf.puts '</xtce:SpaceSystem>'
      tf.close
      tf
    end
    def basic_types
      tf = Tempfile.new(['unittest', '.xtce'])
      tf.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"TGT1\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      tf.puts "  <xtce:TelemetryMetaData>"
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "      <xtce:IntegerParameterType name=\"OPCODE_Type\" shortDescription=\"Opcode\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "      <xtce:EnumeratedParameterType name=\"UNSIGNED_Type\" shortDescription=\"Unsigned\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "        <xtce:EnumerationList>"
      tf.puts "          <xtce:Enumeration value=\"0\" label=\"FALSE\"/>"
      tf.puts "          <xtce:Enumeration value=\"1\" label=\"TRUE\"/>"
      tf.puts "        </xtce:EnumerationList>"
      tf.puts "      </xtce:EnumeratedParameterType>"
      tf.puts "      <xtce:IntegerParameterType name=\"SIGNED_Type\" shortDescription=\"Signed\" signed=\"true\">"
      tf.puts "        <xtce:UnitSet>"
      tf.puts "          <xtce:Unit description=\"Kilos\">K</xtce:Unit>"
      tf.puts "        </xtce:UnitSet>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"twosComplement\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "      <xtce:IntegerParameterType name=\"ARRAY_ITEM_Type\" shortDescription=\"Array\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "      <xtce:ArrayParameterType name=\"ARRAY_ITEM_ArrayType\" shortDescription=\"Array\" arrayTypeRef=\"ARRAY_ITEM_Type\">"
      tf.puts "        <xtce:DimensionList>"
      tf.puts "          <xtce:Dimension>"
      tf.puts "            <xtce:StartingIndex>"
      tf.puts "              <xtce:FixedValue>0</xtce:FixedValue>"
      tf.puts "            </xtce:StartingIndex>"
      tf.puts "            <xtce:EndingIndex>"
      # 80 bits of 8 bit items is 10 elements, so the inclusive ending index is 9
      tf.puts "              <xtce:FixedValue>9</xtce:FixedValue>"
      tf.puts "            </xtce:EndingIndex>"
      tf.puts "          </xtce:Dimension>"
      tf.puts "        </xtce:DimensionList>"
      tf.puts "      </xtce:ArrayParameterType>"
      tf.puts "      <xtce:FloatParameterType name=\"FLOAT_Type\" sizeInBits=\"32\" shortDescription=\"Float\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:FloatDataEncoding sizeInBits=\"32\" encoding=\"IEEE754_1985\">"
      tf.puts "          <xtce:DefaultCalibrator>"
      tf.puts "            <xtce:PolynomialCalibrator>"
      tf.puts "              <xtce:Term coefficient=\"10.0\" exponent=\"0\"/>"
      tf.puts "              <xtce:Term coefficient=\"0.5\" exponent=\"1\"/>"
      tf.puts "              <xtce:Term coefficient=\"0.25\" exponent=\"2\"/>"
      tf.puts "            </xtce:PolynomialCalibrator>"
      tf.puts "          </xtce:DefaultCalibrator>"
      tf.puts "        </xtce:FloatDataEncoding>"
      tf.puts "      </xtce:FloatParameterType>"
      tf.puts "      <xtce:FloatParameterType name=\"DOUBLE_Type\" sizeInBits=\"64\" shortDescription=\"Double\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:FloatDataEncoding sizeInBits=\"64\" encoding=\"IEEE754_1985\"/>"
      tf.puts "        <xtce:DefaultAlarm>"
      tf.puts "          <xtce:StaticAlarmRanges>"
      tf.puts "            <xtce:WarningRange minInclusive=\"-70.0\" maxInclusive=\"60.0\"/>"
      tf.puts "            <xtce:CriticalRange minInclusive=\"-80.0\" maxInclusive=\"80.0\"/>"
      tf.puts "          </xtce:StaticAlarmRanges>"
      tf.puts "        </xtce:DefaultAlarm>"
      tf.puts "      </xtce:FloatParameterType>"
      tf.puts "      <xtce:StringParameterType name=\"STRING_Type\" characterWidth=\"8\" shortDescription=\"String\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:StringDataEncoding encoding=\"UTF-8\">"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:Fixed>"
      tf.puts "              <xtce:FixedValue>32</xtce:FixedValue>"
      tf.puts "            </xtce:Fixed>"
      tf.puts "            <xtce:TerminationChar>00</xtce:TerminationChar>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:StringDataEncoding>"
      tf.puts "      </xtce:StringParameterType>"
      tf.puts "      <xtce:BinaryParameterType name=\"BLOCK_Type\" shortDescription=\"Block\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:BinaryDataEncoding>"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:FixedValue>32</xtce:FixedValue>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:BinaryDataEncoding>"
      tf.puts "      </xtce:BinaryParameterType>"
      tf.puts "      <xtce:IntegerParameterType name=\"NOT_PACKED_Type\" shortDescription=\"Not packed\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"8\" encoding=\"unsigned\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "    </xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "      <xtce:Parameter name=\"OPCODE\" parameterTypeRef=\"OPCODE_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"UNSIGNED\" parameterTypeRef=\"UNSIGNED_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"SIGNED\" parameterTypeRef=\"SIGNED_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"ARRAY_ITEM\" parameterTypeRef=\"ARRAY_ITEM_ArrayType\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"ARRAY.ITEM\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "      </xtce:Parameter>"
      tf.puts "      <xtce:Parameter name=\"FLOAT\" parameterTypeRef=\"FLOAT_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"DOUBLE\" parameterTypeRef=\"DOUBLE_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"STRING\" parameterTypeRef=\"STRING_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"BLOCK\" parameterTypeRef=\"BLOCK_Type\"/>"
      tf.puts "      <xtce:Parameter name=\"NOT_PACKED\" parameterTypeRef=\"NOT_PACKED_Type\"/>"
      tf.puts "    </xtce:ParameterSet>"
      tf.puts "    <xtce:ContainerSet>"
      tf.puts "      <xtce:SequenceContainer name=\"TLM_PKT_Base\" abstract=\"true\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"OPCODE\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>0</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"UNSIGNED\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>8</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"SIGNED\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>16</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ArrayParameterRefEntry parameterRef=\"ARRAY_ITEM\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>24</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "            <xtce:DimensionList>"
      tf.puts "              <xtce:Dimension>"
      tf.puts "                <xtce:StartingIndex>"
      tf.puts "                  <xtce:FixedValue>0</xtce:FixedValue>"
      tf.puts "                </xtce:StartingIndex>"
      tf.puts "                <xtce:EndingIndex>"
      tf.puts "                  <xtce:FixedValue>9</xtce:FixedValue>"
      tf.puts "                </xtce:EndingIndex>"
      tf.puts "              </xtce:Dimension>"
      tf.puts "            </xtce:DimensionList>"
      tf.puts "          </xtce:ArrayParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"FLOAT\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>104</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"DOUBLE\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>136</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"STRING\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>200</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"BLOCK\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>232</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"NOT_PACKED\">"
      tf.puts "            <xtce:LocationInContainerInBits referenceLocation=\"containerStart\">"
      tf.puts "              <xtce:FixedValue>300</xtce:FixedValue>"
      tf.puts "            </xtce:LocationInContainerInBits>"
      tf.puts "          </xtce:ParameterRefEntry>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "      <xtce:SequenceContainer name=\"TLM_PKT\" shortDescription=\"Telemetry\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"TLM/PKT\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "        <xtce:EntryList/>"
      tf.puts "        <xtce:BaseContainer containerRef=\"TLM_PKT_Base\">"
      tf.puts "          <xtce:RestrictionCriteria>"
      tf.puts "            <xtce:ComparisonList>"
      tf.puts "              <xtce:Comparison parameterRef=\"OPCODE\" value=\"1\"/>"
      tf.puts "            </xtce:ComparisonList>"
      tf.puts "          </xtce:RestrictionCriteria>"
      tf.puts "        </xtce:BaseContainer>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "    </xtce:ContainerSet>"
      tf.puts "  </xtce:TelemetryMetaData>"
      tf.puts "  <xtce:CommandMetaData>"
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "      <xtce:IntegerParameterType name=\"CMD_OPCODE_Type\" initialValue=\"0\" shortDescription=\"Opcode\" signed=\"false\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"unsigned\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:ValidRange minInclusive=\"0\" maxInclusive=\"0\"/>"
      tf.puts "      </xtce:IntegerParameterType>"
      tf.puts "    </xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "      <xtce:Parameter name=\"CMD_OPCODE\" parameterTypeRef=\"CMD_OPCODE_Type\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"OPCODE\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "      </xtce:Parameter>"
      tf.puts "    </xtce:ParameterSet>"
      tf.puts "    <xtce:ArgumentTypeSet>"
      tf.puts "      <xtce:EnumeratedArgumentType name=\"CMD_PKT_CMD_UNSIGNED_Type\" initialValue=\"TRUE\" shortDescription=\"Unsigned\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"unsigned\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:EnumerationList>"
      tf.puts "          <xtce:Enumeration value=\"0\" label=\"FALSE\"/>"
      tf.puts "          <xtce:Enumeration value=\"1\" label=\"TRUE\"/>"
      tf.puts "        </xtce:EnumerationList>"
      tf.puts "      </xtce:EnumeratedArgumentType>"
      tf.puts "      <xtce:IntegerArgumentType name=\"CMD_PKT_CMD_SIGNED_Type\" initialValue=\"0\" shortDescription=\"Signed\" signed=\"true\">"
      tf.puts "        <xtce:UnitSet>"
      tf.puts "          <xtce:Unit description=\"Kilos\">K</xtce:Unit>"
      tf.puts "        </xtce:UnitSet>"
      tf.puts "        <xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"twosComplement\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:ValidRangeSet>"
      tf.puts "          <xtce:ValidRange minInclusive=\"-100\" maxInclusive=\"100\"/>"
      tf.puts "        </xtce:ValidRangeSet>"
      tf.puts "      </xtce:IntegerArgumentType>"
      tf.puts "      <xtce:FloatArgumentType name=\"CMD_PKT_CMD_ARRAY_Type\" sizeInBits=\"64\" shortDescription=\"Array of 10 64bit floats\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:FloatDataEncoding sizeInBits=\"64\" encoding=\"IEEE754_1985\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "      </xtce:FloatArgumentType>"
      tf.puts "      <xtce:ArrayArgumentType name=\"CMD_PKT_CMD_ARRAY_ArrayType\" shortDescription=\"Array of 10 64bit floats\" arrayTypeRef=\"CMD_PKT_CMD_ARRAY_Type\">"
      tf.puts "        <xtce:DimensionList>"
      tf.puts "          <xtce:Dimension>"
      tf.puts "            <xtce:StartingIndex>"
      tf.puts "              <xtce:FixedValue>0</xtce:FixedValue>"
      tf.puts "            </xtce:StartingIndex>"
      tf.puts "            <xtce:EndingIndex>"
      tf.puts "              <xtce:FixedValue>9</xtce:FixedValue>"
      tf.puts "            </xtce:EndingIndex>"
      tf.puts "          </xtce:Dimension>"
      tf.puts "        </xtce:DimensionList>"
      tf.puts "      </xtce:ArrayArgumentType>"
      tf.puts "      <xtce:FloatArgumentType name=\"CMD_PKT_CMD_FLOAT_Type\" sizeInBits=\"32\" initialValue=\"10.0\" shortDescription=\"Float\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:FloatDataEncoding sizeInBits=\"32\" encoding=\"IEEE754_1985\" byteOrder=\"leastSignificantByteFirst\">"
      tf.puts "          <xtce:DefaultCalibrator>"
      tf.puts "            <xtce:PolynomialCalibrator>"
      tf.puts "              <xtce:Term coefficient=\"10.0\" exponent=\"0\"/>"
      tf.puts "              <xtce:Term coefficient=\"0.5\" exponent=\"1\"/>"
      tf.puts "              <xtce:Term coefficient=\"0.25\" exponent=\"2\"/>"
      tf.puts "            </xtce:PolynomialCalibrator>"
      tf.puts "          </xtce:DefaultCalibrator>"
      tf.puts "        </xtce:FloatDataEncoding>"
      # MIN / MAX on a 32 bit FLOAT argument is a finite range, which FloatRangeType
      # (xs:double) can express
      tf.puts "        <xtce:ValidRangeSet>"
      tf.puts "          <xtce:ValidRange minInclusive=\"-3.402823e+38\" maxInclusive=\"3.402823e+38\"/>"
      tf.puts "        </xtce:ValidRangeSet>"
      tf.puts "      </xtce:FloatArgumentType>"
      tf.puts "      <xtce:FloatArgumentType name=\"CMD_PKT_CMD_DOUBLE_Type\" sizeInBits=\"64\" initialValue=\"0.0\" shortDescription=\"Double\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:FloatDataEncoding sizeInBits=\"64\" encoding=\"IEEE754_1985\" byteOrder=\"leastSignificantByteFirst\"/>"
      tf.puts "        <xtce:ValidRangeSet>"
      tf.puts "          <xtce:ValidRange minInclusive=\"-1.7976931348623157e+308\" maxInclusive=\"1.7976931348623157e+308\"/>"
      tf.puts "        </xtce:ValidRangeSet>"
      tf.puts "      </xtce:FloatArgumentType>"
      # String initialValue is the value itself, unquoted
      tf.puts "      <xtce:StringArgumentType name=\"CMD_PKT_CMD_STRING_Type\" characterWidth=\"8\" initialValue=\"DEAD\" shortDescription=\"String\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:StringDataEncoding encoding=\"UTF-8\">"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:Fixed>"
      tf.puts "              <xtce:FixedValue>32</xtce:FixedValue>"
      tf.puts "            </xtce:Fixed>"
      tf.puts "            <xtce:TerminationChar>00</xtce:TerminationChar>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:StringDataEncoding>"
      tf.puts "      </xtce:StringArgumentType>"
      tf.puts "      <xtce:StringArgumentType name=\"CMD_PKT_CMD_STRING2_Type\" characterWidth=\"8\" initialValue=\"0xDEAD\" shortDescription=\"Binary\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:StringDataEncoding encoding=\"UTF-8\">"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:Fixed>"
      tf.puts "              <xtce:FixedValue>32</xtce:FixedValue>"
      tf.puts "            </xtce:Fixed>"
      tf.puts "            <xtce:TerminationChar>00</xtce:TerminationChar>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:StringDataEncoding>"
      tf.puts "      </xtce:StringArgumentType>"
      tf.puts "      <xtce:BinaryArgumentType name=\"CMD_PKT_CMD_BLOCK_Type\" initialValue=\"BEEF\" shortDescription=\"Block\">"
      tf.puts "        <xtce:UnitSet/>"
      tf.puts "        <xtce:BinaryDataEncoding>"
      tf.puts "          <xtce:SizeInBits>"
      tf.puts "            <xtce:FixedValue>32</xtce:FixedValue>"
      tf.puts "          </xtce:SizeInBits>"
      tf.puts "        </xtce:BinaryDataEncoding>"
      tf.puts "      </xtce:BinaryArgumentType>"
      tf.puts "    </xtce:ArgumentTypeSet>"
      tf.puts "    <xtce:MetaCommandSet>"
      tf.puts "      <xtce:MetaCommand name=\"CMD_PKT_Base\" abstract=\"true\">"
      tf.puts "        <xtce:ArgumentList>"
      tf.puts "          <xtce:Argument name=\"CMD_UNSIGNED\" argumentTypeRef=\"CMD_PKT_CMD_UNSIGNED_Type\" initialValue=\"TRUE\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_SIGNED\" argumentTypeRef=\"CMD_PKT_CMD_SIGNED_Type\" initialValue=\"0\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_ARRAY\" argumentTypeRef=\"CMD_PKT_CMD_ARRAY_ArrayType\" initialValue=\"\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_FLOAT\" argumentTypeRef=\"CMD_PKT_CMD_FLOAT_Type\" initialValue=\"10.0\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_DOUBLE\" argumentTypeRef=\"CMD_PKT_CMD_DOUBLE_Type\" initialValue=\"0.0\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_STRING\" argumentTypeRef=\"CMD_PKT_CMD_STRING_Type\" initialValue=\"DEAD\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_STRING2\" argumentTypeRef=\"CMD_PKT_CMD_STRING2_Type\" initialValue=\"0xDEAD\"/>"
      tf.puts "          <xtce:Argument name=\"CMD_BLOCK\" argumentTypeRef=\"CMD_PKT_CMD_BLOCK_Type\" initialValue=\"BEEF\"/>"
      tf.puts "        </xtce:ArgumentList>"
      tf.puts "        <xtce:CommandContainer name=\"CMD_PKT_CommandsBase\">"
      tf.puts "          <xtce:EntryList>"
      tf.puts "            <xtce:ParameterRefEntry parameterRef=\"CMD_OPCODE\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_UNSIGNED\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_SIGNED\"/>"
      tf.puts "            <xtce:ArrayArgumentRefEntry argumentRef=\"CMD_ARRAY\">"
      tf.puts "              <xtce:DimensionList>"
      tf.puts "                <xtce:Dimension>"
      tf.puts "                  <xtce:StartingIndex>"
      tf.puts "                    <xtce:FixedValue>0</xtce:FixedValue>"
      tf.puts "                  </xtce:StartingIndex>"
      tf.puts "                  <xtce:EndingIndex>"
      tf.puts "                    <xtce:FixedValue>9</xtce:FixedValue>"
      tf.puts "                  </xtce:EndingIndex>"
      tf.puts "                </xtce:Dimension>"
      tf.puts "              </xtce:DimensionList>"
      tf.puts "            </xtce:ArrayArgumentRefEntry>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_FLOAT\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_DOUBLE\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_STRING\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_STRING2\"/>"
      tf.puts "            <xtce:ArgumentRefEntry argumentRef=\"CMD_BLOCK\"/>"
      tf.puts "          </xtce:EntryList>"
      tf.puts "        </xtce:CommandContainer>"
      tf.puts "      </xtce:MetaCommand>"
      tf.puts "      <xtce:MetaCommand name=\"CMD_PKT\" shortDescription=\"Command\">"
      tf.puts "        <xtce:AliasSet>"
      tf.puts "          <xtce:Alias nameSpace=\"COSMOS\" alias=\"CMD/PKT\"/>"
      tf.puts "        </xtce:AliasSet>"
      tf.puts "        <xtce:BaseMetaCommand metaCommandRef=\"CMD_PKT_Base\"/>"
      tf.puts "        <xtce:CommandContainer name=\"CMD_PKT_Commands\">"
      tf.puts "          <xtce:EntryList/>"
      tf.puts "          <xtce:BaseContainer containerRef=\"CMD_PKT_CommandsBase\">"
      tf.puts "            <xtce:RestrictionCriteria>"
      tf.puts "              <xtce:ComparisonList>"
      tf.puts "                <xtce:Comparison parameterRef=\"CMD_OPCODE\" value=\"0\"/>"
      tf.puts "              </xtce:ComparisonList>"
      tf.puts "            </xtce:RestrictionCriteria>"
      tf.puts "          </xtce:BaseContainer>"
      tf.puts "        </xtce:CommandContainer>"
      tf.puts "      </xtce:MetaCommand>"
      tf.puts "    </xtce:MetaCommandSet>"
      tf.puts "  </xtce:CommandMetaData>"
      tf.puts "</xtce:SpaceSystem>"
      tf.close
      tf
    end

    def algorithm_xtce
      tf = Tempfile.new(["unittest", ".xtce"])

      tf.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"TGT1\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      tf.puts "  <xtce:TelemetryMetaData>"
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "<!--TODO: "
      tf.puts "	<xtce:TODOParameterType name=\"ITEM1_DERIVED_Type\" shortDescription=\"DERIVED Item\" />"
      tf.puts "-->"
      tf.puts ""
      tf.puts "<!--TODO: "
      tf.puts "	<xtce:TODOParameterType name=\"ITEM2_DERIVED_Type\" shortDescription=\"DERIVED Item\" />"
      tf.puts "-->"
      tf.puts "<xtce:IntegerParameterType name=\"ID_Type\" shortDescription=\"Integer Item\" signed=\"true\"><xtce:UnitSet/><xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"twosComplement\" byteOrder=\"leastSignificantByteFirst\"/></xtce:IntegerParameterType></xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "<!-- TODO: "
      tf.puts "	<xtce:Parameter name=\"ITEM1_DERIVED\" parameterTypeRef=\"ITEM1_DERIVED_Type\">"
      tf.puts "\t\t<xtce:ParameterProperties dataSource=\"derived\"/>"
      tf.puts "		<xtce:AliasSet>"
      tf.puts "			<xtce:Alias nameSpace=\"COSMOS\" alias=\"ITEM1_DERIVED\"/>"
      tf.puts "		</xtce:AliasSet>"
      tf.puts "	</xtce:Parameter>"
      tf.puts "-->"
      tf.puts ""
      tf.puts "<!-- TODO: "
      tf.puts "	<xtce:Parameter name=\"ITEM2_DERIVED\" parameterTypeRef=\"ITEM2_DERIVED_Type\">"
      tf.puts "\t\t<xtce:ParameterProperties dataSource=\"derived\"/>"
      tf.puts "		<xtce:AliasSet>"
      tf.puts "			<xtce:Alias nameSpace=\"COSMOS\" alias=\"ITEM2_DERIVED\"/>"
      tf.puts "		</xtce:AliasSet>"
      tf.puts "	</xtce:Parameter>"
      tf.puts "-->"
      tf.puts "<xtce:Parameter name=\"ID\" parameterTypeRef=\"ID_Type\"/></xtce:ParameterSet>"
      tf.puts "    <xtce:ContainerSet>"
      tf.puts "      <xtce:SequenceContainer name=\"PKT2\" shortDescription=\"Packet\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"ID\"/>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "      <xtce:SequenceContainer name=\"PKT1\" shortDescription=\"Packet\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"ID\"/>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "    </xtce:ContainerSet>"
      tf.puts "  </xtce:TelemetryMetaData>"
      tf.puts "  <!--TODO "
      tf.puts "<AlgorithmSet>"
      tf.puts "  <CustomAlgorithm name=\"PKT2_ITEM2_DERIVED_Conversion2\">"
      tf.puts "    <ExternalAlgorithmSet>"
      tf.puts "      <ExternalAlgorithm implementationName=\"TODO\" algorithmLocation=\"TODO\"/>"
      tf.puts "    </ExternalAlgorithmSet>"
      tf.puts "    <InputSet>"
      tf.puts "      <InputParameterInstanceRef parameterRef=\"TODO\" instance=\"0\" useCalibratedValue=\"TODO\"/>"
      tf.puts "    </InputSet>"
      tf.puts "    <OutputSet>"
      tf.puts "      <OutputParameterRef parameterRef=\"ITEM2_DERIVED\"/>"
      tf.puts "    </OutputSet>"
      tf.puts "    <TriggerSet name=\"triggerSet\">"
      tf.puts "      <OnParameterUpdateTrigger parameterRef=\"TODO\"/>"
      tf.puts "    </TriggerSet>"
      tf.puts "  </CustomAlgorithm>"
      tf.puts "  <CustomAlgorithm name=\"PKT1_ITEM1_DERIVED_Conversion2\">"
      tf.puts "    <ExternalAlgorithmSet>"
      tf.puts "      <ExternalAlgorithm implementationName=\"TODO\" algorithmLocation=\"TODO\"/>"
      tf.puts "    </ExternalAlgorithmSet>"
      tf.puts "    <InputSet>"
      tf.puts "      <InputParameterInstanceRef parameterRef=\"TODO\" instance=\"0\" useCalibratedValue=\"TODO\"/>"
      tf.puts "    </InputSet>"
      tf.puts "    <OutputSet>"
      tf.puts "      <OutputParameterRef parameterRef=\"ITEM1_DERIVED\"/>"
      tf.puts "    </OutputSet>"
      tf.puts "    <TriggerSet name=\"triggerSet\">"
      tf.puts "      <OnParameterUpdateTrigger parameterRef=\"TODO\"/>"
      tf.puts "    </TriggerSet>"
      tf.puts "  </CustomAlgorithm>"
      tf.puts "</AlgorithmSet>"
      tf.puts ""
      tf.puts "-->"
      tf.puts "</xtce:SpaceSystem>"
      tf.close
      tf
    end

    def special_packet_time_xtce
      tf = Tempfile.new(["unittest", ".xtce"])

      tf.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      tf.puts "<xtce:SpaceSystem xmlns:xtce=\"http://www.omg.org/spec/XTCE/20180204\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" name=\"TGT1\" xsi:schemaLocation=\"http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd\">"
      tf.puts "  <xtce:TelemetryMetaData>"
      tf.puts "    <xtce:ParameterTypeSet>"
      tf.puts "<xtce:IntegerParameterType name=\"ID_Type\" shortDescription=\"Integer Item\" signed=\"true\"><xtce:UnitSet/><xtce:IntegerDataEncoding sizeInBits=\"16\" encoding=\"twosComplement\" byteOrder=\"leastSignificantByteFirst\"/></xtce:IntegerParameterType></xtce:ParameterTypeSet>"
      tf.puts "    <xtce:ParameterSet>"
      tf.puts "<!-- TODO: "
      tf.puts "	<xtce:Parameter name=\"PACKET_TIME\" parameterTypeRef=\"PACKET_TIME_Type\">"
      tf.puts "		<xtce:ParameterProperties dataSource=\"derived\"/>"
      tf.puts "	</xtce:Parameter>"
      tf.puts "-->"
      tf.puts "<xtce:Parameter name=\"ID\" parameterTypeRef=\"ID_Type\"><xtce:ParameterProperties><xtce:TimeAssociation parameterRef=\"PACKET_TIME\"/></xtce:ParameterProperties></xtce:Parameter></xtce:ParameterSet>"
      tf.puts "    <xtce:ContainerSet>"
      tf.puts "      <xtce:SequenceContainer name=\"PKT1\" shortDescription=\"Packet\">"
      tf.puts "        <xtce:EntryList>"
      tf.puts "          <xtce:ParameterRefEntry parameterRef=\"ID\"/>"
      tf.puts "        </xtce:EntryList>"
      tf.puts "      </xtce:SequenceContainer>"
      tf.puts "    </xtce:ContainerSet>"
      tf.puts "  </xtce:TelemetryMetaData>"
      tf.puts "</xtce:SpaceSystem>"
      tf.close
      tf
    end


    describe "Convert CMD and TLM definitions" do
      before(:each) do
        @pc = PacketConfig.new
      end

      after(:each) do
        # Several tests here define a top-level Conversion2 class via `load`. Ruby
        # reopens (not replaces) the constant, so a custom initialize would leak
        # into other spec files that also define Conversion2. Remove it to isolate.
        Object.send(:remove_const, :Conversion2) if Object.const_defined?(:Conversion2)
      end

      # Validate a generated XTCE file against the vendored OMG XTCE 1.2 schema.
      # The schema imports xml.xsd via a relative path, so validate from within the
      # schema directory to resolve it offline.
      def assert_xtce_schema_valid(xml_path)
        errors = XtceConverter.schema_errors(xml_path)
        expect(errors).to be_empty, "XTCE 1.2 schema validation errors:\n#{errors.join("\n")}"
      end

      it "converts simple tlm and aliases name" do
        expected_tf = telemetry_file("TGT1") do |telem_file|
          sample_simple_tlm_packet_with_alias(telem_file)
        end
        tf = Tempfile.new('unittest')
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(xtce_doc).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts simple cmd and aliases name" do
        expected_tf = command_file("TGT1") do |cmd_file|
          sample_simple_cmd_packet_with_alias(cmd_file)
        end
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        Nokogiri::XML(File.open(xml_path))
        Nokogiri::XML(File.open(expected_tf.path))
        expected_tf.unlink
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts tlm packet with dynamic string" do
        expected_tf = telemetry_file("TGT1") do |file|
          sample_tlm_with_dynamic_string(file)
        end
        tf = Tempfile.new('unittest')
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM OPCODE 0 8 UINT 0 \"OPCODE Description\"\n"\
               "  APPEND_ITEM DYNAMIC 0 STRING \"DYNAMIC Description\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(xtce_doc).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts adds ancillary data to indicate packet is 'ALLOW_SHORT'" do
        expected_tf = telemetry_file("TGT1") do |file|
          sample_simple_tlm_packet_with_alias(file, with_allow_short: true)
        end
        tf = Tempfile.new('unittest')
        tlm1 = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ALLOW_SHORT \n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf.puts tlm1
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(xtce_doc).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "comibnes two targets' xtce files with no root specified" do
        expected_tf = no_root_specified("TGT1", "TGT2")
        tf_tgt1 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt1.puts tlm
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt1.puts cmd
        tf_tgt1.close
        @pc.process_file(tf_tgt1.path, "TGT1")
        tf_tgt2 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT2 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt2.puts tlm
        cmd = "COMMAND TGT2 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt2.puts cmd
        tf_tgt2.close
        @pc.process_file(tf_tgt2.path, "TGT2")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        combination_dir = File.join(spec_install)
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        assert_xtce_schema_valid(output_path)
        result_xml = Nokogiri::XML(File.open(output_path))

        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(result_xml).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf_tgt1.unlink
        tf_tgt2.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
        FileUtils.rm_rf File.join(spec_install, "TGT2")
        FileUtils.rm_rf File.join(spec_install, "TARGETS_COMBINED")
      end

      it "combines two targets' xtce files with TGT1 as the root" do
        expected_tf = root_specified("TGT1", "TGT2")
        tf_tgt1 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt1.puts tlm
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt1.puts cmd
        tf_tgt1.close
        @pc.process_file(tf_tgt1.path, "TGT1")
        tf_tgt2 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT2 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt2.puts tlm
        cmd = "COMMAND TGT2 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt2.puts cmd
        tf_tgt2.close
        @pc.process_file(tf_tgt2.path, "TGT2")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        combination_dir = File.join(spec_install)
        output_path = XtceConverter.combine_output_xtce(combination_dir, "TGT1")
        assert_xtce_schema_valid(output_path)
        result_xml = Nokogiri::XML(File.open(output_path))

        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(result_xml).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf_tgt1.unlink
        tf_tgt2.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
        FileUtils.rm_rf File.join(spec_install, "TGT2")
        FileUtils.rm_rf File.join(spec_install, "TARGETS_COMBINED")
      end

      it "combines two targets' xtce files with TGT2 as the root" do
        expected_tf = root_specified("TGT2", "TGT1")
        tf_tgt1 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt1.puts tlm
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt1.puts cmd
        tf_tgt1.close
        @pc.process_file(tf_tgt1.path, "TGT1")
        tf_tgt2 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT2 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt2.puts tlm
        cmd = "COMMAND TGT2 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt2.puts cmd
        tf_tgt2.close
        @pc.process_file(tf_tgt2.path, "TGT2")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        combination_dir = File.join(spec_install)
        output_path = XtceConverter.combine_output_xtce(combination_dir, "TGT2")
        assert_xtce_schema_valid(output_path)
        result_xml = Nokogiri::XML(File.open(output_path))
        expected_output = Nokogiri::XML(File.open(expected_tf.path))
        expect(result_xml).to be_equivalent_to(expected_output)
        expected_tf.unlink
        tf_tgt1.unlink
        tf_tgt2.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
        FileUtils.rm_rf File.join(spec_install, "TGT2")
        FileUtils.rm_rf File.join(spec_install, "TARGETS_COMBINED")
      end

      it "does not combine xtce since no target exists" do
        spec_install = File.join("..", "..", "install")
        combination_dir = File.join(spec_install)
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        expect(output_path).to be_equivalent_to(nil)
      end

      it "does not combine xtce since only one target exists" do
        tf_tgt1 = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"TLMPKT Description\"\n"\
               "  ID_ITEM TLM.OPCODE 0 8 UINT 0 \"TLM_OPCODE Description\"\n"
        tf_tgt1.puts tlm
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD[0].ATTRIBUTES/ID 0 16 UINT 0 0 0 \"CMD_ID Description\"\n"\
              "  PARAMETER CMD[0].ATTRIBUTES/BOOL 16 16 UINT 0 65535 1 \"Unsigned\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf_tgt1.puts cmd
        tf_tgt1.close
        @pc.process_file(tf_tgt1.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        combination_dir = File.join(spec_install)
        output_path = XtceConverter.combine_output_xtce(combination_dir)
        expect(output_path).to be_equivalent_to(nil)
        tf_tgt1.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end


      it "converts basic types provided in cosmos definitions" do
        expected_tf = basic_types()
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMD/PKT LITTLE_ENDIAN \"Command\"\n"\
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
        tlm1 = "TELEMETRY TGT1 TLM/PKT BIG_ENDIAN \"Telemetry\"\n"\
               "  ID_ITEM OPCODE 0 8 UINT 1 \"Opcode\"\n"\
               "  ITEM UNSIGNED 8 8 UINT \"Unsigned\"\n"\
               "    STATE FALSE 0\n"\
               "    STATE TRUE 1\n"\
               "  ITEM SIGNED 16 8 INT \"Signed\"\n"\
               "    UNITS Kilos K\n"\
               "  ARRAY_ITEM ARRAY.ITEM 24 8 UINT 80 \"Array\"\n"\
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
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_result_xml = Nokogiri::XML(File.open(expected_tf))
        expect(xtce_doc).to be_equivalent_to(expected_result_xml)
        expected_tf.unlink
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "generates XTCE that validates against the OMG XTCE 1.2 schema" do
        tf = Tempfile.new('unittest')
        # Include an array argument to exercise ArrayArgumentRefEntry, which the
        # XTCE 1.2 schema requires to use argumentRef (not parameterRef).
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  ARRAY_PARAMETER CMD_ARRAY 16 64 FLOAT 640 \"Array of 10 64bit floats\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "rejects ArrayArgumentRefEntry using parameterRef against the XTCE 1.2 schema" do
        # Guards the fix for the regression where array command arguments were
        # exported with parameterRef. The XTCE 1.2 schema requires argumentRef, so
        # the buggy form below must be reported as invalid.
        buggy = <<~XTCE
          <?xml version="1.0" encoding="UTF-8"?>
          <xtce:SpaceSystem xmlns:xtce="http://www.omg.org/spec/XTCE/20180204" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="TGT1" xsi:schemaLocation="http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd">
            <xtce:CommandMetaData>
              <xtce:ArgumentTypeSet>
                <xtce:FloatArgumentType name="CMDPKT_CMD_ARRAY_Type" sizeInBits="64">
                  <xtce:UnitSet/>
                  <xtce:FloatDataEncoding sizeInBits="64" encoding="IEEE754_1985"/>
                </xtce:FloatArgumentType>
                <xtce:ArrayArgumentType name="CMDPKT_CMD_ARRAY_ArrayType" arrayTypeRef="CMDPKT_CMD_ARRAY_Type">
                  <xtce:DimensionList>
                    <xtce:Dimension>
                      <xtce:StartingIndex><xtce:FixedValue>0</xtce:FixedValue></xtce:StartingIndex>
                      <xtce:EndingIndex><xtce:FixedValue>0</xtce:FixedValue></xtce:EndingIndex>
                    </xtce:Dimension>
                  </xtce:DimensionList>
                </xtce:ArrayArgumentType>
              </xtce:ArgumentTypeSet>
              <xtce:MetaCommandSet>
                <xtce:MetaCommand name="CMDPKT">
                  <xtce:ArgumentList>
                    <xtce:Argument name="CMD_ARRAY" argumentTypeRef="CMDPKT_CMD_ARRAY_ArrayType"/>
                  </xtce:ArgumentList>
                  <xtce:CommandContainer name="CMDPKT_Commands">
                    <xtce:EntryList>
                      <xtce:ArrayArgumentRefEntry parameterRef="CMD_ARRAY">
                        <xtce:DimensionList>
                          <xtce:Dimension>
                            <xtce:StartingIndex><xtce:FixedValue>0</xtce:FixedValue></xtce:StartingIndex>
                            <xtce:EndingIndex><xtce:FixedValue>9</xtce:FixedValue></xtce:EndingIndex>
                          </xtce:Dimension>
                        </xtce:DimensionList>
                      </xtce:ArrayArgumentRefEntry>
                    </xtce:EntryList>
                  </xtce:CommandContainer>
                </xtce:MetaCommand>
              </xtce:MetaCommandSet>
            </xtce:CommandMetaData>
          </xtce:SpaceSystem>
        XTCE
        tf = Tempfile.new(['unittest', '.xtce'])
        tf.write(buggy)
        tf.close
        messages = XtceConverter.schema_errors(tf.path).join("\n")
        tf.unlink
        expect(messages).to match(/parameterRef.*not allowed/)
        expect(messages).to match(/argumentRef.*required/)
      end

      it "converts little endian conversions, ranges and unpacked items" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT LITTLE_ENDIAN \"Command\"\n"\
              "  PARAMETER CMD_INT 0 16 INT -100 100 0 \"Int with a conversion\"\n"\
              "    POLY_WRITE_CONVERSION 10.0 0.5\n"\
              "  PARAMETER CMD_FLOAT 16 32 FLOAT -1.5 1.5 0.0 \"Float with a range\"\n"
        tf.puts cmd
        # A second packet sharing the ID parameter name exercises the unique ID lookup
        cmd2 = "COMMAND TGT1 CMDPKT2 LITTLE_ENDIAN \"Command\"\n"\
               "  ID_PARAMETER OPCODE 0 8 UINT 0 1 1 \"Opcode\"\n"\
               "COMMAND TGT1 CMDPKT3 LITTLE_ENDIAN \"Command\"\n"\
               "  ID_PARAMETER OPCODE 0 8 UINT 0 1 0 \"Opcode\"\n"
        tf.puts cmd2
        # A gap between items makes the packet unpacked, which locates each entry
        # explicitly. TRAILER is relative to the end of the packet.
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM HEAD 0 8 UINT \"Head\"\n"\
              "  ITEM TRAILER -16 16 UINT \"Trailer\"\n"\
              "  ITEM DERIVED_ITEM 0 0 DERIVED \"Derived without a conversion\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # An integer with a polynomial conversion is exported as a float type
        int_encoding = doc.at_xpath("//FloatArgumentType[@name='CMDPKT_CMD_INT_Type']/IntegerDataEncoding")
        expect(int_encoding['byteOrder']).to eql "leastSignificantByteFirst"
        expect(int_encoding.at_xpath("DefaultCalibrator")).to_not be_nil

        float_range = doc.at_xpath("//FloatArgumentType[@name='CMDPKT_CMD_FLOAT_Type']/ValidRangeSet/ValidRange")
        expect(float_range['minInclusive']).to eql "-1.5"
        expect(float_range['maxInclusive']).to eql "1.5"

        trailer = doc.at_xpath("//ParameterRefEntry[@parameterRef='TRAILER']/LocationInContainerInBits")
        expect(trailer['referenceLocation']).to eql "containerEnd"
        expect(trailer.at_xpath("FixedValue").text).to eql "16"

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "round trips BLOCK defaults as hexBinary" do
        tf = Tempfile.new('unittest')
        # BLOCK initialValue is xs:hexBinary regardless of whether the bytes happen
        # to be printable, so both defaults export as raw hex digits.
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  PARAMETER PRINTABLE 16 32 BLOCK \"DEAD\" \"Printable block\"\n"\
              "  PARAMETER UNPRINTABLE 48 32 BLOCK 0xDEADBEEF \"Unprintable block\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        printable = doc.at_xpath("//BinaryArgumentType[@name='CMDPKT_PRINTABLE_Type']")
        expect(printable['initialValue']).to eql "44454144"
        unprintable = doc.at_xpath("//BinaryArgumentType[@name='CMDPKT_UNPRINTABLE_Type']")
        expect(unprintable['initialValue']).to eql "DEADBEEF"

        # Importing the generated file gives back the original defaults
        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        packet = pc.commands["TGT1"]["CMDPKT"]
        expect(packet.get_item("PRINTABLE").default).to eql "DEAD"
        expect(packet.get_item("UNPRINTABLE").default).to eql "\xDE\xAD\xBE\xEF"

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "round trips STRING defaults without quoting them" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER OPCODE 0 16 UINT 0 0 0 \"Opcode\"\n"\
              "  PARAMETER STR 16 32 STRING \"DEAD\" \"String\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # A quoted initialValue would make the quotes part of the default for every
        # reader but our own importer
        str_type = doc.at_xpath("//StringArgumentType[@name='CMDPKT_STR_Type']")
        expect(str_type['initialValue']).to eql "DEAD"

        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        expect(pc.commands["TGT1"]["CMDPKT"].get_item("STR").default).to eql "DEAD"

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "still imports the quoted STRING defaults written by COSMOS 7.2 and earlier" do
        tf = Tempfile.new(['unittest', '.xtce'])
        tf.puts <<~XTCE
          <?xml version="1.0" encoding="UTF-8"?>
          <xtce:SpaceSystem xmlns:xtce="http://www.omg.org/spec/XTCE/20180204" name="TGT1">
            <xtce:CommandMetaData>
              <xtce:ArgumentTypeSet>
                <xtce:StringArgumentType name="STR_Type" characterWidth="8" initialValue="&quot;DEAD&quot;">
                  <xtce:UnitSet/>
                  <xtce:StringDataEncoding encoding="UTF-8">
                    <xtce:SizeInBits>
                      <xtce:Fixed><xtce:FixedValue>32</xtce:FixedValue></xtce:Fixed>
                    </xtce:SizeInBits>
                  </xtce:StringDataEncoding>
                </xtce:StringArgumentType>
              </xtce:ArgumentTypeSet>
              <xtce:MetaCommandSet>
                <xtce:MetaCommand name="CMDPKT">
                  <xtce:ArgumentList>
                    <xtce:Argument name="STR" argumentTypeRef="STR_Type"/>
                  </xtce:ArgumentList>
                  <xtce:CommandContainer name="CMDPKT_Commands">
                    <xtce:EntryList>
                      <xtce:ArgumentRefEntry argumentRef="STR"/>
                    </xtce:EntryList>
                  </xtce:CommandContainer>
                </xtce:MetaCommand>
              </xtce:MetaCommandSet>
            </xtce:CommandMetaData>
          </xtce:SpaceSystem>
        XTCE
        tf.close
        @pc.process_file(tf.path, "TGT1")
        expect(@pc.commands["TGT1"]["CMDPKT"].get_item("STR").default).to eql "DEAD"
        tf.unlink
      end

      it "emits no ParameterTypeSet when a target's items are all DERIVED" do
        tf = Tempfile.new('unittest')
        # An empty ParameterTypeSet / ParameterSet is invalid per the schema
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Derived only\"\n"\
              "  ITEM DERIVED_ITEM 0 0 DERIVED \"Derived\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        expect(doc.at_xpath("//ParameterTypeSet")).to be_nil
        expect(doc.at_xpath("//ParameterSet")).to be_nil

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "does not emit a container that inherits from itself" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ID_ITEM OPCODE 0 8 UINT 1 \"Opcode\"\n"\
              "  ITEM VALUE 8 16 UINT \"Value\"\n"
        tf.puts tlm
        # A distinct ID name so the exporter's CMD_ prefix for names shared with
        # telemetry doesn't come into it
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER FUNC_CODE 0 8 UINT 1 1 1 \"Function code\"\n"\
              "  PARAMETER ARG 8 16 UINT 0 100 0 \"Arg\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # The ID comparisons need a BaseContainer, which must reference something other
        # than its own container or consumers resolving inheritance hit a cycle
        containers = doc.xpath("//SequenceContainer | //CommandContainer")
        expect(containers.size).to be > 0
        containers.each do |container|
          base = container.at_xpath("BaseContainer")
          next unless base

          expect(base['containerRef']).to_not eql container['name']
        end
        expect(doc.at_xpath("//SequenceContainer[@name='TLMPKT']/BaseContainer")['containerRef']).to eql "TLMPKT_Base"
        expect(doc.at_xpath("//SequenceContainer[@name='TLMPKT_Base']")['abstract']).to eql "true"
        expect(doc.at_xpath("//MetaCommand[@name='CMDPKT']/BaseMetaCommand")['metaCommandRef']).to eql "CMDPKT_Base"

        # And the packets still import with all their items and ID values
        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        packet = pc.telemetry["TGT1"]["TLMPKT"]
        expect(packet.sorted_items.map(&:name)).to include("OPCODE", "VALUE")
        expect(packet.get_item("OPCODE").id_value).to eql 1
        command = pc.commands["TGT1"]["CMDPKT"]
        expect(command.sorted_items.map(&:name)).to include("FUNC_CODE", "ARG")
        expect(command.get_item("FUNC_CODE").id_value).to eql 1

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "only emits a ValidRange the schema can express" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  PARAMETER U64 0 64 UINT MIN MAX 0 \"Uint64\"\n"\
              "  PARAMETER F64 64 64 FLOAT MIN MAX 0.0 \"Float64\"\n"\
              "  PARAMETER I16 128 16 INT -100 100 0 \"Int16\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # A full 64 bit UINT range exceeds IntegerRangeType's xs:long bounds
        expect(doc.at_xpath("//IntegerArgumentType[@name='CMDPKT_U64_Type']/ValidRangeSet")).to be_nil
        # FloatRangeType is xs:double, so even the FLOAT MIN / MAX defaults fit
        float_range = doc.at_xpath("//FloatArgumentType[@name='CMDPKT_F64_Type']/ValidRangeSet/ValidRange")
        expect(float_range['minInclusive'].to_f).to eql(-Float::MAX)
        expect(float_range['maxInclusive'].to_f).to eql Float::MAX
        int_range = doc.at_xpath("//IntegerArgumentType[@name='CMDPKT_I16_Type']/ValidRangeSet/ValidRange")
        expect(int_range['minInclusive']).to eql "-100"
        expect(int_range['maxInclusive']).to eql "100"

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "references arguments by the name they are declared with" do
        tf = Tempfile.new('unittest')
        # A command argument sharing a name with a telemetry parameter used to be
        # referenced as CMD_<NAME> while still being declared as <NAME>, which the
        # schema cannot catch (refs are plain strings) and which fails to re-import
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  APPEND_ID_ITEM ID 16 INT 1 \"Identifier\"\n"\
              "  APPEND_ITEM VALUE 32 FLOAT \"Value\"\n"
        tf.puts tlm
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  APPEND_ID_PARAMETER ID 16 INT 1 1 1 \"Identifier\"\n"\
              "  APPEND_PARAMETER VALUE 32 FLOAT 0 10 5 \"Value\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        declared = doc.xpath("//ArgumentList/Argument").map { |node| node['name'] }
        referenced = doc.xpath("//EntryList/ArgumentRefEntry | //EntryList/ArrayArgumentRefEntry").map do |node|
          node['argumentRef']
        end
        expect(referenced).to_not be_empty
        expect(referenced - declared).to be_empty
        # The ID item is a Parameter in CommandMetaData, where CMD_ does disambiguate it
        # from the telemetry parameter of the same name
        expect(doc.at_xpath("//CommandMetaData//Parameter[@name='CMD_ID']")).to_not be_nil

        # And the file imports, which it could not do with a dangling reference
        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        expect(pc.commands["TGT1"]["CMDPKT"].get_item("VALUE").default).to eql 5.0

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "round trips a packet with gaps between items" do
        tf = Tempfile.new('unittest')
        # Unpacked items carry a LocationInContainerInBits each, which is what lets the
        # gaps survive. The last item is positioned from the container end.
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ID_ITEM ID 0 16 UINT 1 \"Identifier\"\n"\
              "  ITEM AFTER_GAP 32 16 UINT \"Item after a 16 bit gap\"\n"\
              "  ITEM TRAILER -16 16 UINT \"Item from the end\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        original = @pc.telemetry["TGT1"]["TLMPKT"].sorted_items.reject { |item| item.data_type == :DERIVED }
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        reimported = pc.telemetry["TGT1"]["TLMPKT"].sorted_items.reject { |item| item.data_type == :DERIVED }

        expect(reimported.map(&:name)).to eql original.map(&:name)
        expect(reimported.map(&:bit_offset)).to eql original.map(&:bit_offset)
        expect(reimported.map(&:bit_size)).to eql original.map(&:bit_size)

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "round trips item names it had to change to write valid XTCE" do
        tf = Tempfile.new('unittest')
        # Two reasons a written name differs from the item name: characters XTCE forbids,
        # and the CMD_ prefix on a command ID parameter sharing a telemetry name. Both
        # are recorded in a COSMOS AliasSet, which the importer reads back.
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  APPEND_ID_ITEM ID 16 UINT 1 \"Identifier\"\n"
        tf.puts tlm
        cmd = "COMMAND TGT1 CMDPKT BIG_ENDIAN \"Command\"\n"\
              "  APPEND_ID_PARAMETER ID 16 UINT 1 1 1 \"Identifier\"\n"\
              "  APPEND_PARAMETER ARG[0].VALUE 16 UINT 0 100 5 \"Mangled name\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # Written names are XTCE safe and the originals are carried in an alias
        expect(doc.at_xpath("//CommandMetaData//Parameter[@name='CMD_ID']/AliasSet/Alias")['alias']).to eql "ID"
        expect(doc.at_xpath("//Argument[@name='ARG_0__VALUE']/AliasSet/Alias")['alias']).to eql "ARG[0].VALUE"

        pc = PacketConfig.new
        pc.process_file(xml_path, "TGT1")
        command = pc.commands["TGT1"]["CMDPKT"]
        expect(command.sorted_items.map(&:name)).to include("ID", "ARG[0].VALUE")
        expect(command.get_item("ID").id_value).to eql 1
        expect(command.get_item("ARG[0].VALUE").default).to eql 5

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "uses whatever item name it is given for the TimeAssociation" do
        tf = Tempfile.new('unittest')
        # Nothing about the time association is specific to the name PACKET_TIME, which
        # is what makes the --time_association_name CLI flag worth passing through
        tf.puts 'TELEMETRY TGT1 TLMPKT LITTLE_ENDIAN "Packet"'
        tf.puts '  ID_ITEM ID 0 16 INT 1 "Integer Item"'
        tf.puts '  ITEM MY_TIME 16 32 UINT "Time item"'
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "MY_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        association = doc.at_xpath("//Parameter[@name='ID']/ParameterProperties/TimeAssociation")
        expect(association['parameterRef']).to eql "MY_TIME"
        associations = doc.xpath("//ParameterProperties/TimeAssociation")
        expect(associations.map { |node| node['parameterRef'] }.uniq).to eql ["MY_TIME"]
        # The time item is the source of the association, not a subject of it
        expect(doc.at_xpath("//Parameter[@name='MY_TIME']/ParameterProperties")).to be_nil
        expect(associations.length).to eql doc.xpath("//ParameterSet/Parameter").length - 1

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "validates a file against the vendored schema from any working directory" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ID_ITEM OPCODE 0 8 UINT 1 \"Opcode\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.expand_path(File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce"))

        # The schema imports xml.xsd relative to itself, so a naive File.read of it only
        # resolves when the process happens to be sitting in the schema directory
        Dir.chdir(Dir.tmpdir) do
          expect(XtceConverter.schema_errors(xml_path)).to be_empty
          expect(XtceConverter.xtce_namespace(xml_path)).to eql XtceConverter::XTCE_1_2_NAMESPACE
        end

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "reports schema errors and the declared namespace of an older file" do
        tf = Tempfile.new(['unittest', '.xtce'])
        tf.puts <<~XTCE
          <?xml version="1.0" encoding="UTF-8"?>
          <xtce:SpaceSystem xmlns:xtce="http://www.omg.org/space/xtce" name="TGT1">
            <xtce:TelemetryMetaData>
              <xtce:ParameterTypeSet/>
            </xtce:TelemetryMetaData>
          </xtce:SpaceSystem>
        XTCE
        tf.close

        # An XTCE 1.0 file is not measured against the 1.2 schema, it just reports which
        # namespace it declared so a caller can skip validation
        expect(XtceConverter.xtce_namespace(tf.path)).to eql "http://www.omg.org/space/xtce"
        expect(XtceConverter.schema_errors(tf.path)).to_not be_empty
        tf.unlink
      end

      it "sizes an array type's dimension from the element count" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLMPKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ARRAY_ITEM ARRAY_ITEM 0 8 UINT 80 \"Array of 10 8 bit items\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)

        doc = Nokogiri::XML(File.read(xml_path))
        doc.remove_namespaces!
        # One dimension is the single Dimension element; the indices are inclusive and
        # give that dimension's length, so 10 elements ends at 9
        dimensions = doc.xpath("//ArrayParameterType[@name='ARRAY_ITEM_ArrayType']/DimensionList/Dimension")
        expect(dimensions.size).to eql 1
        expect(dimensions[0].at_xpath("StartingIndex/FixedValue").text).to eql "0"
        expect(dimensions[0].at_xpath("EndingIndex/FixedValue").text).to eql "9"

        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end


      it "converts the DERIVED Tlm" do
        filename = File.join(File.dirname(__FILE__), "../../conversion2.rb")
        File.open(filename, 'w') do |file|
          file.puts "require 'openc3/conversions/conversion'"
          file.puts "class Conversion2 < OpenC3::Conversion"
          file.puts "  def initialize(parameter_name)"
          file.puts "    super()"
          file.puts "    @converted_type = :STRING"
          file.puts "    @parameter_name = parameter_name"
          file.puts "    @converted_bit_size = 0"
          file.puts "    @params = nil"
          file.puts "  end"
          file.puts "  def call(value, packet, buffer)"
          file.puts "    value * 2"
          file.puts "  end"
          file.puts "end"
        end
        saved_verbose = $VERBOSE
        $VERBOSE = nil
        load 'conversion2.rb'
        $VERBOSE = saved_verbose

        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT1 pkt1 LITTLE_ENDIAN "Packet"'
        tf.puts '  ITEM ID 0 16 INT "Integer Item"'
        tf.puts '  APPEND_ITEM item1.derived 0 DERIVED "DERIVED Item"'
        tf.puts '  READ_CONVERSION conversion2.rb ID'
        tf.puts '                                       '
        tf.puts 'TELEMETRY TGT1 pkt2 LITTLE_ENDIAN "Packet"'
        tf.puts '  ITEM ID 0 16 INT "Integer Item"'
        tf.puts '  APPEND_ITEM item1.derived 0 DERIVED "DERIVED Item"'
        tf.puts '  READ_CONVERSION conversion2.rb ID'
        tf.puts '  APPEND_ITEM item2.derived 0 DERIVED "DERIVED Item"'
        tf.puts '  READ_CONVERSION conversion2.rb ID'
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_xtce_file = algorithm_xtce()
        expected_result_xml = Nokogiri::XML(File.open(expected_xtce_file))
        string_output = xtce_doc.canonicalize(nil, nil, true)
        expected_string_output = expected_result_xml.canonicalize(nil, nil, true)
        expect(string_output).to eq(expected_string_output)
        tf.unlink
        expected_xtce_file.unlink
        File.delete(filename) if File.exist?(filename)
      end

      it "converts the PACKET_TIME special case" do
        filename = File.join(File.dirname(__FILE__), "../../conversion2.rb")
        File.open(filename, 'w') do |file|
          file.puts "require 'openc3/conversions/conversion'"
          file.puts "class Conversion2 < OpenC3::Conversion"
          file.puts "  def initialize(parameter_name)"
          file.puts "    super()"
          file.puts "    @converted_type = :STRING"
          file.puts "    @parameter_name = parameter_name"
          file.puts "    @converted_bit_size = 0"
          file.puts "    @params = nil"
          file.puts "  end"
          file.puts "  def call(value, packet, buffer)"
          file.puts "    value * 2"
          file.puts "  end"
          file.puts "end"
        end
        saved_verbose = $VERBOSE
        $VERBOSE = nil
        load 'conversion2.rb'
        $VERBOSE = saved_verbose

        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT1 pkt1 LITTLE_ENDIAN "Packet"'
        tf.puts '  ITEM ID 0 16 INT "Integer Item"'
        tf.puts '  APPEND_ITEM PACKET_TIME 0 DERIVED "DERIVED Item"'
        tf.puts '  READ_CONVERSION conversion2.rb ID'
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expected_xtce_file = special_packet_time_xtce()
        expected_result_xml = Nokogiri::XML(File.open(expected_xtce_file))
        string_output = xtce_doc.canonicalize(nil, nil, true)
        expected_string_output = expected_result_xml.canonicalize(nil, nil, true)
        expect(string_output).to eq(expected_string_output)
        tf.unlink
        expected_xtce_file.unlink
        File.delete(filename) if File.exist?(filename)
      end

      it "converts items with read and write conversions" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM ITEM1 0 16 UINT \"Item with conversion\"\n"\
              "    GENERIC_READ_CONVERSION_START\n"\
              "      value * 2\n"\
              "    GENERIC_READ_CONVERSION_END\n"\
              "  ITEM ITEM2 16 16 UINT \"Item with poly conversion\"\n"\
              "    POLY_READ_CONVERSION 1.0 2.0\n"
        tf.puts tlm
        cmd = "COMMAND TGT1 CMD_PKT LITTLE_ENDIAN \"Command\"\n"\
              "  PARAMETER CMD_ITEM1 0 16 UINT 0 65535 0 \"Command item\"\n"\
              "    GENERIC_WRITE_CONVERSION_START\n"\
              "      value / 2\n"\
              "    GENERIC_WRITE_CONVERSION_END\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        # Verify conversions are present
        expect(xtce_doc.to_s).to include("DefaultCalibrator")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts items with limits groups" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM ITEM1 0 16 UINT \"Item with limits\"\n"\
              "    LIMITS DEFAULT 1 ENABLED -10.0 -5.0 5.0 10.0\n"\
              "  ITEM ITEM2 16 16 INT \"Item with limits\"\n"\
              "    LIMITS DEFAULT 1 ENABLED -100 -50 50 100\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        # Verify DEFAULT limits are present
        expect(xtce_doc.to_s).to include("DefaultAlarm")
        expect(xtce_doc.to_s).to include("StaticAlarmRanges")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts items with different endianness" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMD_PKT BIG_ENDIAN \"Command\"\n"\
              "  PARAMETER PARAM1 0 32 UINT 0 100 0 \"Big endian parameter\"\n"\
              "  PARAMETER PARAM2 32 32 UINT 0 100 0 \"Little endian parameter\" LITTLE_ENDIAN\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        # Verify little endian byte order is present
        expect(xtce_doc.to_s).to include("byteOrder=\"leastSignificantByteFirst\"")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "converts boolean parameters" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMD_PKT LITTLE_ENDIAN \"Command\"\n"\
              "  PARAMETER CMD_BOOL 0 8 UINT 0 1 0 \"Boolean parameter\"\n"\
              "    STATE FALSE 0\n"\
              "    STATE TRUE 1\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expect(xtce_doc.to_s).to include("EnumeratedArgumentType")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "handles items with min/max values" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM ITEM1 0 16 INT \"Item with min/max\"\n"\
              "  ITEM ITEM2 16 32 FLOAT \"Float with range\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "handles string with different encodings" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM STR1 0 64 STRING \"String item\"\n"\
              "  ITEM STR2 64 64 STRING \"Another string\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expect(xtce_doc.to_s).to include("StringDataEncoding")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "handles packed vs unpacked items" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ITEM ITEM1 0 8 UINT \"Packed item\"\n"\
              "  ITEM ITEM2 100 8 UINT \"Unpacked item\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        # Unpacked items should have LocationInContainerInBits
        expect(xtce_doc.to_s).to include("LocationInContainerInBits")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "handles multiple id parameters" do
        tf = Tempfile.new('unittest')
        cmd = "COMMAND TGT1 CMD_PKT LITTLE_ENDIAN \"Command\"\n"\
              "  ID_PARAMETER CMD_ID1 0 8 UINT 1 1 1 \"First ID\"\n"\
              "  ID_PARAMETER CMD_ID2 8 8 UINT 2 2 2 \"Second ID\"\n"\
              "  PARAMETER CMD_PARAM 16 16 UINT 0 65535 0 \"Parameter\"\n"
        tf.puts cmd
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        # Should have both ID parameters
        expect(xtce_doc.to_s).to include("CMD_ID1")
        expect(xtce_doc.to_s).to include("CMD_ID2")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end

      it "handles array items in telemetry" do
        tf = Tempfile.new('unittest')
        tlm = "TELEMETRY TGT1 TLM_PKT BIG_ENDIAN \"Telemetry\"\n"\
              "  ARRAY_ITEM ARRAY1 0 8 UINT 80 \"Array of 10 bytes\"\n"\
              "  ITEM ITEM1 80 16 UINT \"Regular item\"\n"
        tf.puts tlm
        tf.close
        @pc.process_file(tf.path, "TGT1")
        spec_install = File.join("..", "..", "install")
        @pc.to_xtce(spec_install, "PACKET_TIME")
        xml_path = File.join(spec_install, "TGT1", "cmd_tlm", "tgt1.xtce")
        assert_xtce_schema_valid(xml_path)
        expect(File.exist?(xml_path)).to be true
        xtce_doc = Nokogiri::XML(File.open(xml_path))
        expect(xtce_doc.to_s).to include("ArrayParameterType")
        expect(xtce_doc.to_s).to include("ArrayParameterRefEntry")
        tf.unlink
        FileUtils.rm_rf File.join(spec_install, "TGT1")
      end
    end
  end
end
