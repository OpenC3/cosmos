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

require 'openc3/utilities/target_file'
require 'openc3/models/target_model'

class Screen < OpenC3::TargetFile
  def self.all(scope)
    result = super(scope, ['screens'])
    # Only list screens belonging to currently installed targets. Modified
    # screens for uninstalled targets remain in storage so they're restored
    # if the target is reinstalled, but they aren't displayed in TlmViewer.
    installed_targets = OpenC3::TargetModel.names(scope: scope)
    screens = []
    result.each do |path|
      filename = path.split('*')[0] # Don't differentiate modified - TODO: Should we?
      next unless File.extname(filename) == ".txt"
      next if File.basename(filename, ".txt")[0] == '_' # underscore filenames are partials
      target = filename.split('/')[0]
      next unless installed_targets.include?(target)
      screens << filename
    end
    screens
  end

  def self.find(scope, target, screen)
    name = screen.split('*')[0].downcase # Split '*' that indicates modified - Filenames are lowercase
    body(scope, "#{target}/screens/#{name}.txt")
  end

  def self.create(scope, target, screen, text)
    name = "#{target}/screens/#{screen.downcase}.txt"
    super(scope, name, text)
  end

  def self.destroy(scope, target, screen)
    name = "#{target}/screens/#{screen.downcase}.txt"
    super(scope, name)
  end
end
