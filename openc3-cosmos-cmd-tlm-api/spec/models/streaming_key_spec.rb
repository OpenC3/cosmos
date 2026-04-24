# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rails_helper'

RSpec.describe StreamingKey, type: :model do
  describe '.parse' do
    context 'RAW packet keys' do
      it 'parses a RAW TLM packet key' do
        key = StreamingKey.parse('RAW__TLM__INST__PARAMS')
        expect(key.stream_mode).to eq(:RAW)
        expect(key.cmd_or_tlm).to eq(:TLM)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to be_nil
        expect(key.value_type).to eq(:RAW)
        expect(key.reduced_type).to be_nil
      end

      it 'parses a RAW CMD packet key' do
        key = StreamingKey.parse('RAW__CMD__INST__COLLECT')
        expect(key.stream_mode).to eq(:RAW)
        expect(key.cmd_or_tlm).to eq(:CMD)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('COLLECT')
        expect(key.value_type).to eq(:RAW)
      end
    end

    context 'DECOM packet keys' do
      it 'parses a DECOM packet key with value type' do
        key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__CONVERTED')
        expect(key.stream_mode).to eq(:DECOM)
        expect(key.cmd_or_tlm).to eq(:TLM)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to be_nil
        expect(key.value_type).to eq(:CONVERTED)
        expect(key.reduced_type).to be_nil
      end

      it 'parses a DECOM CMD packet key' do
        key = StreamingKey.parse('DECOM__CMD__INST__COLLECT__RAW')
        expect(key.stream_mode).to eq(:DECOM)
        expect(key.cmd_or_tlm).to eq(:CMD)
        expect(key.packet_name).to eq('COLLECT')
        expect(key.value_type).to eq(:RAW)
      end
    end

    context 'DECOM item keys' do
      it 'parses a DECOM item key' do
        key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', item_key: true)
        expect(key.stream_mode).to eq(:DECOM)
        expect(key.cmd_or_tlm).to eq(:TLM)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to eq('VALUE1')
        expect(key.value_type).to eq(:CONVERTED)
        expect(key.reduced_type).to be_nil
      end

      it 'parses a DECOM CMD item key' do
        key = StreamingKey.parse('DECOM__CMD__INST__COLLECT__DURATION__RAW', item_key: true)
        expect(key.stream_mode).to eq(:DECOM)
        expect(key.cmd_or_tlm).to eq(:CMD)
        expect(key.packet_name).to eq('COLLECT')
        expect(key.item_name).to eq('DURATION')
        expect(key.value_type).to eq(:RAW)
      end
    end

    context 'reduced mode keys' do
      it 'parses a REDUCED_MINUTE item key' do
        key = StreamingKey.parse('REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG', item_key: true)
        expect(key.stream_mode).to eq(:REDUCED_MINUTE)
        expect(key.cmd_or_tlm).to eq(:TLM)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to eq('VALUE1')
        expect(key.value_type).to eq(:CONVERTED)
        expect(key.reduced_type).to eq(:AVG)
      end

      it 'parses a REDUCED_HOUR item key' do
        key = StreamingKey.parse('REDUCED_HOUR__TLM__INST__HEALTH_STATUS__TEMP1__RAW__MIN', item_key: true)
        expect(key.stream_mode).to eq(:REDUCED_HOUR)
        expect(key.item_name).to eq('TEMP1')
        expect(key.value_type).to eq(:RAW)
        expect(key.reduced_type).to eq(:MIN)
      end

      it 'parses a REDUCED_DAY item key' do
        key = StreamingKey.parse('REDUCED_DAY__TLM__INST__PARAMS__VALUE1__CONVERTED__STDDEV', item_key: true)
        expect(key.stream_mode).to eq(:REDUCED_DAY)
        expect(key.reduced_type).to eq(:STDDEV)
      end

      it 'parses a reduced packet key with value type' do
        key = StreamingKey.parse('REDUCED_MINUTE__TLM__INST__PARAMS__CONVERTED')
        expect(key.stream_mode).to eq(:REDUCED_MINUTE)
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to be_nil
        expect(key.value_type).to eq(:CONVERTED)
        expect(key.reduced_type).to be_nil
      end

      it 'parses a reduced packet key with value type and reduced type' do
        key = StreamingKey.parse('REDUCED_HOUR__TLM__INST__PARAMS__CONVERTED__AVG')
        expect(key.stream_mode).to eq(:REDUCED_HOUR)
        expect(key.packet_name).to eq('PARAMS')
        expect(key.item_name).to be_nil
        expect(key.value_type).to eq(:CONVERTED)
        expect(key.reduced_type).to eq(:AVG)
      end
    end

    context 'case insensitivity' do
      it 'upcases the input' do
        key = StreamingKey.parse('decom__tlm__inst__params__converted')
        expect(key.stream_mode).to eq(:DECOM)
        expect(key.cmd_or_tlm).to eq(:TLM)
        expect(key.target_name).to eq('INST')
        expect(key.packet_name).to eq('PARAMS')
        expect(key.value_type).to eq(:CONVERTED)
      end
    end

    context 'immutability' do
      it 'returns a frozen Data instance' do
        key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__CONVERTED')
        expect(key).to be_frozen
      end
    end
  end

  describe '#to_key_string' do
    it 'round-trips a RAW packet key' do
      original = 'RAW__TLM__INST__PARAMS'
      expect(StreamingKey.parse(original).to_key_string).to eq(original)
    end

    it 'round-trips a DECOM packet key' do
      original = 'DECOM__TLM__INST__PARAMS__CONVERTED'
      expect(StreamingKey.parse(original).to_key_string).to eq(original)
    end

    it 'round-trips a DECOM item key' do
      original = 'DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED'
      expect(StreamingKey.parse(original, item_key: true).to_key_string).to eq(original)
    end

    it 'round-trips a REDUCED_MINUTE item key' do
      original = 'REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__CONVERTED__AVG'
      expect(StreamingKey.parse(original, item_key: true).to_key_string).to eq(original)
    end

    it 'round-trips a REDUCED_HOUR packet key' do
      original = 'REDUCED_HOUR__TLM__INST__PARAMS__CONVERTED__AVG'
      expect(StreamingKey.parse(original).to_key_string).to eq(original)
    end

    it 'round-trips a RAW CMD packet key' do
      original = 'RAW__CMD__INST__COLLECT'
      expect(StreamingKey.parse(original).to_key_string).to eq(original)
    end

    it 'round-trips a DECOM CMD item key' do
      original = 'DECOM__CMD__INST__COLLECT__DURATION__RAW'
      expect(StreamingKey.parse(original, item_key: true).to_key_string).to eq(original)
    end

    it 'round-trips an item key with array brackets' do
      original = 'DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED'
      expect(StreamingKey.parse(original, item_key: true).to_key_string).to eq(original)
    end
  end

  describe '#has_glob?' do
    it 'returns false for a plain item key' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', item_key: true)
      expect(key.has_glob?).to be false
    end

    it 'returns true when item_name contains *' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__TEMP*__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns true when packet_name contains *' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH*__VALUE1__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns true when item_name contains ?' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__TEMP?__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns false when item_name is an array index [0]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__ARY[0]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be false
    end

    it 'returns false when item_name is a multi-digit array index [12]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__ARY[12]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be false
    end

    it 'returns false when item_name has a bracket literal like BRACKET[0]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__BRACKET[0]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be false
    end

    it 'returns false when item_name is a large array index [999]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__DATA[999]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be false
    end

    it 'returns true when item_name contains a bracket range [1-3]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__TEMP[1-3]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns true when item_name contains a letter bracket range [A-C]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__ITEM[A-C]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns true when item_name contains a bracket negation [!0]' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH_STATUS__TEMP[!0]__CONVERTED', item_key: true)
      expect(key.has_glob?).to be true
    end

    it 'returns false for a packet key without item_name' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__CONVERTED')
      expect(key.has_glob?).to be false
    end

    it 'returns true when packet_name has glob in a packet key' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH*__CONVERTED')
      expect(key.has_glob?).to be true
    end
  end

  describe '#packet_type' do
    it 'returns :TLM for TLM keys' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__CONVERTED')
      expect(key.packet_type).to eq(:TLM)
    end

    it 'returns :CMD for CMD keys' do
      key = StreamingKey.parse('DECOM__CMD__INST__COLLECT__RAW')
      expect(key.packet_type).to eq(:CMD)
    end
  end

  describe '#packet_glob?' do
    it 'returns false for a concrete packet name' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__TEMP1__CONVERTED', item_key: true)
      expect(key.packet_glob?).to be false
    end

    it 'returns true when packet_name contains *' do
      key = StreamingKey.parse('DECOM__TLM__INST__HEALTH*__TEMP1__CONVERTED', item_key: true)
      expect(key.packet_glob?).to be true
    end

    it 'returns false when packet_name has array index brackets [0]' do
      key = StreamingKey.parse('DECOM__TLM__INST__PKT[0]__TEMP1__CONVERTED', item_key: true)
      expect(key.packet_glob?).to be false
    end

    it 'returns true when packet_name has bracket range' do
      key = StreamingKey.parse('DECOM__TLM__INST__PKT[1-3]__TEMP1__CONVERTED', item_key: true)
      expect(key.packet_glob?).to be true
    end
  end

  describe '#item_glob?' do
    it 'returns false for a concrete item name' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__VALUE1__CONVERTED', item_key: true)
      expect(key.item_glob?).to be false
    end

    it 'returns true when item_name contains *' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__TEMP*__CONVERTED', item_key: true)
      expect(key.item_glob?).to be true
    end

    it 'returns false when item_name is nil (packet key)' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__CONVERTED')
      expect(key.item_glob?).to be false
    end

    it 'returns false when item_name has array index [0]' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__ARY[0]__CONVERTED', item_key: true)
      expect(key.item_glob?).to be false
    end

    it 'returns true when item_name has bracket range [1-3]' do
      key = StreamingKey.parse('DECOM__TLM__INST__PARAMS__TEMP[1-3]__CONVERTED', item_key: true)
      expect(key.item_glob?).to be true
    end
  end

  describe '#with' do
    it 'creates a new key with a replaced field' do
      key = StreamingKey.parse('DECOM__TLM__INST__LATEST__VALUE1__CONVERTED', item_key: true)
      updated = key.with(packet_name: 'HEALTH_STATUS')
      expect(updated.packet_name).to eq('HEALTH_STATUS')
      expect(updated.target_name).to eq('INST')
      expect(updated.item_name).to eq('VALUE1')
      expect(updated.value_type).to eq(:CONVERTED)
      expect(updated.to_key_string).to eq('DECOM__TLM__INST__HEALTH_STATUS__VALUE1__CONVERTED')
    end

    it 'does not mutate the original key' do
      key = StreamingKey.parse('DECOM__TLM__INST__LATEST__VALUE1__CONVERTED', item_key: true)
      key.with(packet_name: 'HEALTH_STATUS')
      expect(key.packet_name).to eq('LATEST')
    end
  end
end
