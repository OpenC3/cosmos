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

require 'openc3/utilities/target_file'
require 'openc3/models/target_model'

# Dashboards are plain text definitions stored with a target just like screens:
# TARGET/dashboards/<name>.txt. A dashboard may display items from any target,
# the owning target only determines where the file lives.
class Dashboard < OpenC3::TargetFile
  def self.all(scope)
    result = super(scope, ['dashboards'])
    # Only list dashboards belonging to currently installed targets
    installed_targets = OpenC3::TargetModel.names(scope: scope)
    dashboards = []
    result.each do |path|
      filename = strip_modified(path)
      next unless File.extname(filename) == ".txt"
      next if File.basename(filename, ".txt")[0] == '_' # underscore filenames are partials
      target = filename.split('/')[0]
      next unless installed_targets.include?(target)
      dashboards << filename
    end
    dashboards
  end

  def self.find(scope, target, dashboard)
    name = strip_modified(dashboard).downcase # Filenames are lowercase
    body(scope, "#{target}/dashboards/#{name}.txt")
  end

  def self.create(scope, target, dashboard, text)
    name = "#{target}/dashboards/#{dashboard.downcase}.txt"
    super(scope, name, text)
  end

  def self.destroy(scope, target, dashboard)
    name = "#{target}/dashboards/#{dashboard.downcase}.txt"
    super(scope, name)
  end
end
