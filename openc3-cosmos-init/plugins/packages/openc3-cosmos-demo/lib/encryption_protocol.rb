# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Example encryption protocol using AES-256-GCM
# This demonstrates how to implement encryption at the protocol layer

require 'openssl'
require 'openc3/interfaces/protocols/protocol'

module OpenC3
  class EncryptionProtocol < Protocol
    # @param key [String] Hex-encoded 32-byte encryption key (64 hex chars)
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(key, allow_empty_data = nil)
      super(allow_empty_data)
      # Convert hex string to binary key
      @key = [key].pack('H*')
      raise "Key must be 32 bytes (64 hex characters)" unless @key.length == 32
      # Create cipher instances once and reuse them
      @cipher = OpenSSL::Cipher.new('aes-256-gcm')
      @decipher = OpenSSL::Cipher.new('aes-256-gcm')
    end

    def read_data(data, extra = nil)
      return super(data, extra) if data.empty?

      begin
        @decipher.reset
        @decipher.decrypt
        @decipher.key = @key

        # Extract IV and auth tag from the data
        # Format: [12-byte IV][16-byte auth tag][ciphertext]
        iv = data[0..11]
        auth_tag = data[12..27]
        ciphertext = data[28..-1]

        @decipher.iv = iv
        @decipher.auth_tag = auth_tag

        plaintext = @decipher.update(ciphertext) + @decipher.final
        return plaintext, extra
      rescue OpenSSL::Cipher::CipherError => e
        Logger.error("EncryptionProtocol: Decryption failed: #{e.message}")
        return :DISCONNECT
      end
    end

    def write_data(data, extra = nil)
      return super(data, extra) if data.empty?

      @cipher.reset
      @cipher.encrypt
      @cipher.key = @key

      # Generate a random IV for each message (recommended for GCM)
      iv = @cipher.random_iv
      @cipher.iv = iv

      ciphertext = @cipher.update(data) + @cipher.final
      auth_tag = @cipher.auth_tag

      # Prepend IV and auth tag to ciphertext
      # Format: [12-byte IV][16-byte auth tag][ciphertext]
      encrypted_data = iv + auth_tag + ciphertext
      return encrypted_data, extra
    end
  end
end
