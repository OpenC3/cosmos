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
  # Two target subdirectories hold definitions whose GENERIC_READ_CONVERSION /
  # GENERIC_WRITE_CONVERSION blocks are evaluated as code:
  #   - <TARGET>/cmd_tlm/...: loaded by System.setup_targets and processed by
  #     PacketConfig in the decom microservices. Only the server-side
  #     dynamic-packet mechanism (TargetModel#dynamic_update) writes that area
  #     without going through an API request.
  #   - <TARGET>/tables/config/...: table definitions, processed by TableConfig
  #     in cmd-tlm-api for every Table Manager operation.
  # Writing either is therefore an admin operation, matching the tier COSMOS
  # requires everywhere else code is introduced (plugin install).
  #
  # Every API writer that can reach the overlay must consult these predicates:
  #   - storage_controller#get_upload_presigned_request / delete (presigned S3 upload)
  #   - tables_controller#save / save_as / report / destroy (Table -> TargetFile)
  #   - scripts_controller#create / destroy (Script -> TargetFile)
  module ConfigOverlay
    # Config bucket areas a non-admin is allowed to write at all
    NON_ADMIN_AREAS = ['targets_modified', 'tmp'].freeze

    # Target subdirectories whose contents are executed as code
    CODE_AREAS = [['cmd_tlm'], ['tables', 'config']].freeze

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

    # True if the overlay-relative name targets a code area (cmd_tlm or
    # tables/config), i.e. writing it requires admin. Name is relative to
    # targets_modified/, e.g. "<TARGET>/cmd_tlm/tlm.txt". Fails closed (true)
    # on non-canonical names.
    def self.code_overlay?(name)
      parts = canonical_parts(name)
      return true if parts.nil?
      code_area?(parts)
    end

    # True if the target-relative name is a canonical table definition path,
    # e.g. "<TARGET>/tables/config/table_def.txt". Table only parses definitions
    # from here, so a definition can't be pointed at a non-admin overlay area.
    def self.table_definition?(name)
      parts = canonical_parts(name)
      return false if parts.nil?
      parts.length > 3 and parts[1, 2] == ['tables', 'config']
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
      return false if area == 'targets_modified' && code_area?(parts[2..])
      true
    end

    # target_parts: <TARGET> / <subdir> / ...
    def self.code_area?(target_parts)
      CODE_AREAS.any? { |area| target_parts[1, area.length] == area }
    end
    private_class_method :code_area?
  end
end
