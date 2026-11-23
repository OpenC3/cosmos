# encoding: utf-8

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/store'

module OpenC3
  # Registry of protected storage locations. A location is a bucket or volume
  # (named by its OPENC3_*_BUCKET / OPENC3_*_VOLUME environment variable) plus
  # an optional key prefix. Bucket Explorer hides protected locations from, and
  # refuses access to, everyone but system administrators (superadmin).
  class ProtectedStorageModel
    KEY = 'openc3__protected_storage'

    # @param root [String] Environment variable name such as OPENC3_CONFIG_BUCKET
    # @param prefix [String] Key prefix to protect. An empty prefix protects the whole root.
    def self.add(root:, prefix: '')
      Store.sadd(KEY, "#{root}:#{normalize_prefix(prefix)}")
    end

    # @param root [String] Environment variable name such as OPENC3_CONFIG_BUCKET
    # @param key [String] Key or path within the root
    # @param contains [Boolean] Also true if a protected location is inside key,
    #   i.e. key is a parent that would include protected content (used for directory deletes)
    # @return [Boolean] true if key is a protected prefix or inside one
    def self.protected?(root:, key:, contains: false)
      key = normalize_key(key)
      dir = key.empty? ? '' : "#{key}/"
      prefixes_for(root).any? { |prefix| dir.start_with?(prefix) || (contains && prefix.start_with?(dir)) }
    end

    # @return [Boolean] true if any location is protected for the root
    def self.any?(root:)
      !prefixes_for(root).empty?
    end

    # Canonical key: no empty or '.' segments, so no leading, trailing or doubled slashes.
    # Storage backends resolve './' and '//' inside a key to the canonical key so a raw
    # comparison could be sidestepped.
    def self.normalize_key(key)
      key.to_s.split('/').reject { |part| part.empty? || part == '.' }.join('/')
    end

    def self.normalize_prefix(prefix)
      prefix = normalize_key(prefix)
      prefix.empty? ? '' : "#{prefix}/"
    end

    def self.prefixes_for(root)
      marker = "#{root}:"
      Store.smembers(KEY).select { |member| member.start_with?(marker) }.map { |member| member[marker.length..] }
    end
    private_class_method :prefixes_for
  end
end
