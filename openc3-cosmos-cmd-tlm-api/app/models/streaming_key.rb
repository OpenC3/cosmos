# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

StreamingKey = Data.define(:stream_mode, :cmd_or_tlm, :target_name, :packet_name, :item_name, :value_type, :reduced_type) do
  # Parse a __-delimited streaming key string into a StreamingKey.
  #
  # Item keys have the format:
  #   MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE[__REDUCEDTYPE]
  #
  # Packet keys have the format:
  #   MODE__CMDORTLM__TARGET__PACKET[__VALUETYPE[__REDUCEDTYPE]]
  #
  # RAW packet keys omit VALUETYPE (it is implicitly :RAW):
  #   RAW__CMDORTLM__TARGET__PACKET
  def self.parse(key_string, item_key: false)
    key_string = key_string.upcase
    parts = key_string.split('__')
    stream_mode = parts[0].to_s.intern
    cmd_or_tlm = parts[1].to_s.intern
    target_name = parts[2].to_s
    packet_name = parts[3].to_s
    item_name = nil
    value_type = nil
    reduced_type = nil

    if stream_mode == :RAW
      value_type = :RAW
    elsif item_key
      item_name = parts[4].to_s
      value_type = parts[5].to_s.intern
      reduced_type = parts[6].to_s.intern if parts.length >= 7
    else
      value_type = parts[4].to_s.intern if parts.length >= 5
      reduced_type = parts[5].to_s.intern if parts.length >= 6
    end

    new(
      stream_mode: stream_mode,
      cmd_or_tlm: cmd_or_tlm,
      target_name: target_name,
      packet_name: packet_name,
      item_name: item_name,
      value_type: value_type,
      reduced_type: reduced_type
    )
  end

  # Returns :CMD or :TLM based on cmd_or_tlm.
  def packet_type
    (cmd_or_tlm == :CMD) ? :CMD : :TLM
  end

  # Returns true if packet_name contains glob wildcard characters.
  def packet_glob?
    !!(packet_name && packet_name.match?(/[*?\[]/))
  end

  # Returns true if item_name contains glob wildcard characters.
  def item_glob?
    !!(item_name && item_name.match?(/[*?\[]/))
  end

  # Returns true if packet_name or item_name contain glob wildcard characters.
  def has_glob?
    packet_glob? || item_glob?
  end

  # Reconstruct the __-delimited key string from fields.
  def to_key_string
    parts = [stream_mode, cmd_or_tlm, target_name, packet_name]
    parts << item_name if item_name
    parts << value_type if value_type && stream_mode != :RAW
    parts << reduced_type if reduced_type
    parts.join('__')
  end
end
