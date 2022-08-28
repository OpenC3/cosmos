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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'openc3'
require 'tempfile'
require 'openc3/utilities/target_file'
require 'openc3/utilities/s3'
OpenC3.require_file 'openc3/utilities/store'
OpenC3.require_file 'openc3/tools/table_manager/table_manager_core'

class Table < OpenC3::TargetFile
  def self.all(scope)
    super(scope, ['tables'])
  end

  def self.binary(scope, binary_filename, definition_filename = nil, table_name = nil)
    binary = OpenStruct.new
    binary.filename = File.basename(binary_filename)
    binary.contents = body(scope, binary_filename)
    if definition_filename && table_name
      root_definition = get_definitions(scope, definition_filename)
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
      root_definition = get_definitions(scope, definition_filename)
      definition.filename, definition.contents =
        OpenC3::TableManagerCore.definition(root_definition, table_name)
    else
      definition.filename = File.basename(definition_filename)
      definition.contents = body(scope, definition_filename)
    end
    return definition
  end

  def self.report(scope, binary_filename, definition_filename, table_name = nil)
    report = OpenStruct.new
    binary = body(scope, binary_filename)
    root_definition = get_definitions(scope, definition_filename)
    if table_name
      # Convert the typical table naming convention of all caps with underscores
      # to the typical binary convention of camelcase, e.g. MC_CONFIG => McConfig.bin
      filename = table_name.split('_').map { |part| part.capitalize }.join()
      report.filename = "#{filename}.csv"
    else
      report.filename = File.basename(binary_filename).sub('.bin', '.csv')
    end
    report.contents = OpenC3::TableManagerCore.report(binary, root_definition, table_name)
    create(scope, binary_filename.sub('.bin', '.csv'), report.contents)
    return report
  end

  def self.load(scope, binary_filename, definition_filename)
    binary = body(scope, binary_filename)
    root_definition = get_definitions(scope, definition_filename)
    return OpenC3::TableManagerCore.build_json(binary, root_definition)
  end

  def self.save(scope, binary_filename, definition_filename, tables)
    binary = body(scope, binary_filename)
    raise "Binary file '#{binary_filename}' not found" unless binary
    root_definition = get_definitions(scope, definition_filename)
    binary = OpenC3::TableManagerCore.save(root_definition, JSON.parse(tables, :allow_nan => true, :create_additions => true))
    create(scope, binary_filename, binary, content_type: nil)
  end

  def self.save_as(scope, filename, new_filename)
    file = body(scope, filename)
    raise "File '#{filename}' not found" unless file
    create(scope, new_filename, file, content_type: nil)
  end

  def self.generate(scope, definition_filename)
    root_definition = get_definitions(scope, definition_filename)
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

  def self.get_definitions(scope, definition_filename)
    temp_dir = Dir.mktmpdir
    definition = body(scope, definition_filename)
    base_definition = File.join(temp_dir, File.basename(definition_filename))
    File.write(base_definition, definition)
    # If the definition includes TABLEFILE we need to load
    # the other definitions locally so we can render them
    base_dir = File.dirname(definition_filename)
    definition.split("\n").each do |line|
      if line.strip =~ /^TABLEFILE (.*)/
        filename = File.join(base_dir, $1.remove_quotes)
        file = body(scope, filename)
        raise "Could not find file #{filename}" unless file
        File.write(File.join(temp_dir, File.basename(filename)), file)
      end
    end
    base_definition
  end
end
