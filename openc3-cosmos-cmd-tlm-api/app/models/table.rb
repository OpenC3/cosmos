# encoding: ascii-8bit

# Copyright 2021 Ball Aerospace & Technologies Corp.
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

require 'openc3'
require 'ostruct'
require 'tempfile'
require 'openc3/utilities/target_file'
OpenC3.require_file 'openc3/utilities/store'
OpenC3.require_file 'openc3/tools/table_manager/table_manager_core'

class Table < OpenC3::TargetFile
  class NotFound < StandardError
  end

  def self.all(scope, target = nil)
    super(scope, ['tables'], target: target)
  end

  def self.binary(scope, binary_filename, definition_filename = nil, table_name = nil)
    binary = OpenStruct.new
    binary.filename = File.basename(binary_filename)
    binary.contents = body(scope, binary_filename)
    raise NotFound, "Binary file '#{binary_filename}' not found" unless binary.contents
    # If they want an individual table from the binary we do more work
    if definition_filename and table_name
      root_definition = get_definitions(scope, definition_filename, binary_filename)[0]
      raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
      # Convert the typical table naming convention of all caps with underscores
      # to the typical binary convention of camelcase, e.g. MC_CONFIG => McConfig.bin
      filename = table_name.split('_').map { |part| part.capitalize }.join()
      binary.filename = "#{filename}.bin"
      binary.contents = OpenC3::TableManagerCore.binary(binary.contents, root_definition, table_name)
    end
    return binary
  end

  def self.definition(scope, definition_filename, table_name = nil)
    definition = OpenStruct.new
    if table_name
      root_definition = get_definitions(scope, definition_filename)[0]
      raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
      definition.filename, definition.contents =
        OpenC3::TableManagerCore.definition(root_definition, table_name)
    else
      contents = body(scope, definition_filename)
      raise NotFound, "Definition file '#{definition_filename}' not found" unless contents
      definition.filename = File.basename(definition_filename)
      definition.contents = contents
    end
    return definition
  end

  def self.report(scope, binary_filename, definition_filename, table_name = nil)
    report = OpenStruct.new
    binary = body(scope, binary_filename)
    raise NotFound, "Binary file '#{binary_filename}' not found" unless binary
    root_definition = get_definitions(scope, definition_filename, binary_filename)[0]
    raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
    if table_name
      # Convert the typical table naming convention of all caps with underscores
      # to the typical binary convention of camelcase, e.g. MC_CONFIG => McConfig.bin
      filename = table_name.split('_').map { |part| part.capitalize }.join()
      report.filename = "#{File.dirname(binary_filename)}/#{filename}.csv"
    else
      report.filename = binary_filename.sub('.bin', '.csv')
    end
    report.contents = OpenC3::TableManagerCore.report(binary, root_definition, table_name)
    create(scope, report.filename, report.contents)
    return report
  end

  def self.load(scope, binary_filename, definition_filename)
    binary = body(scope, binary_filename)
    raise NotFound, "Binary file '#{binary_filename}' not found" unless binary
    root_definition, definition_filename = get_definitions(scope, definition_filename, binary_filename)
    raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
    json = OpenC3::TableManagerCore.build_json_hash(binary, root_definition)
    json['definition'] = definition_filename
    return json.to_json(allow_nan: true)
  end

  def self.save(scope, binary_filename, definition_filename, tables)
    binary = body(scope, binary_filename)
    raise NotFound, "Binary file '#{binary_filename}' not found" unless binary
    root_definition = get_definitions(scope, definition_filename, binary_filename)[0]
    raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
    binary = OpenC3::TableManagerCore.save(root_definition, JSON.parse(tables, allow_nan: true, create_additions: true))
    create(scope, binary_filename, binary, content_type: nil)
  end

  def self.save_as(scope, filename, new_filename)
    file = body(scope, filename)
    raise NotFound, "File '#{filename}' not found" unless file
    create(scope, new_filename, file, content_type: nil)
  end

  def self.generate(scope, definition_filename)
    root_definition = get_definitions(scope, definition_filename)[0]
    raise NotFound, "Definition file '#{definition_filename}' not found" unless root_definition
    binary = OpenC3::TableManagerCore.generate(root_definition)
    binary_filename = "#{File.dirname(definition_filename).sub('/config','/bin')}/#{File.basename(definition_filename)}"
    binary_filename.sub!('_def', '') # Strip off _def from the definition filename
    binary_filename.sub!('.txt', '.bin')
    create(scope, binary_filename, binary, content_type: nil)
    return binary_filename
  end

  def self.lock(scope, name, user)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hset("#{scope}__table-locks", name, user)
  end

  def self.unlock(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    OpenC3::Store.hdel("#{scope}__table-locks", name)
  end

  def self.locked?(scope, name)
    name = name.split('*')[0] # Split '*' that indicates modified
    locked_by = OpenC3::Store.hget("#{scope}__table-locks", name)
    locked_by ||= false
    locked_by
  end

  # Private helper methods

  def self.get_definitions(scope, definition_filename, binary_filename = nil)
    temp_dir = Dir.mktmpdir
    definition = body(scope, definition_filename)
    # We might not find the definition, especially if the binary isn't named
    # like the convention. If not, and they pass us a binary filename,
    # then look through all the definitions and try to find a match.
    if !definition and binary_filename
      target = definition_filename.split('/')[0]
      all = OpenC3::TargetFile.all(scope, ['tables'], target: target)
      found = false
      base_binary = File.basename(binary_filename, File.extname(binary_filename))
      all.each do |filename|
        next unless filename.include?('config/')
        base_def = File.basename(filename, File.extname(filename))
        base_def = base_def.sub('_def', '')
        if base_binary == base_def
          found = true
          definition_filename = filename
          break # We found an exact match
        end
        if base_binary.include?(base_def)
          found = true
          definition_filename = filename
          # Don't break because we might find an exact match
        end
      end
      if found
        definition = body(scope, definition_filename)
      else
        return [nil, definition_filename]
      end
    end
    base_definition = File.join(temp_dir, File.basename(definition_filename))
    File.write(base_definition, definition)
    # If the definition includes TABLEFILE we need to load
    # the other definitions locally so we can render them
    base_dir = File.dirname(definition_filename)
    definition.split("\n").each do |line|
      if line.strip =~ /^TABLEFILE (.*)/
        filename = File.join(base_dir, $1.remove_quotes)
        file = body(scope, filename)
        raise NotFound, "Could not find file #{filename}" unless file
        File.write(File.join(temp_dir, File.basename(filename)), file)
      end
    end
    return [base_definition, definition_filename]
  end
end
