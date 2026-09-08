# encoding: ascii-8bit

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

module OpenC3
  # Shared predicates describing which parts of the user-writable config overlay
  # (targets_modified) a non-admin may write.
  #
  # The cmd_tlm overlay (targets_modified/<TARGET>/cmd_tlm/...) is loaded by
  # System.setup_targets and processed by PacketConfig, which evaluates
  # GENERIC_READ_CONVERSION / GENERIC_WRITE_CONVERSION blocks as code in the
  # decom microservices. Writing it is therefore an admin operation, matching the
  # tier COSMOS requires everywhere else code is introduced (plugin install).
  # Only the server-side dynamic-packet mechanism (TargetModel#dynamic_update)
  # writes that area without going through an API request.
  #
  # Every API writer that can reach the overlay must consult these predicates:
  #   - storage_controller#get_upload_presigned_request / delete (presigned S3 upload)
  #   - tables_controller#save / save_as / generate / destroy (Table -> TargetFile)
  #   - scripts_controller#create / destroy (Script -> TargetFile)
  module ConfigOverlay
    # Config bucket areas a non-admin is allowed to write at all
    NON_ADMIN_AREAS = ['targets_modified', 'tmp'].freeze

    # Target subdirectory whose contents are executed as code
    CODE_AREA = 'cmd_tlm'

    # Split a path into segments, or nil if the path is not canonical.
    #
    # Positional segment checks (parts[1], parts[3]) can be bypassed by a path
    # the object store normalizes differently, so empty '//' segments, '.'/'..'
    # segments, and leading/trailing slashes yield nil and every caller fails
    # closed (requires admin) on nil.
    def self.canonical_parts(path)
      return nil if path.nil? || path.empty?
      return nil if path.start_with?('/') || path.end_with?('/')
      parts = path.split('/')
      return nil if parts.any? { |part| part.empty? || part == '.' || part == '..' }
      parts
    end

    # True if the overlay-relative name targets the cmd_tlm subtree, i.e. writing
    # it requires admin. Name is relative to targets_modified/, e.g.
    # "<TARGET>/cmd_tlm/tlm.txt". Fails closed (true) on non-canonical names.
    def self.cmd_tlm_overlay?(name)
      parts = canonical_parts(name)
      return true if parts.nil?
      # parts: <TARGET> / <area> / ...
      parts[1] == CODE_AREA
    end

    # True if the given config bucket key is an overlay path a non-admin may
    # write. Key is the full bucket key, e.g.
    # "<SCOPE>/targets_modified/<TARGET>/screens/x.txt". Fails closed (false) on
    # non-canonical keys.
    def self.non_admin_writable_key?(key)
      parts = canonical_parts(key)
      return false if parts.nil?
      # parts: <SCOPE> / <area> / <TARGET> / <subdir> / ...
      area = parts[1]
      return false unless NON_ADMIN_AREAS.include?(area)
      return false if area == 'targets_modified' && parts[3] == CODE_AREA
      true
    end
  end
end
