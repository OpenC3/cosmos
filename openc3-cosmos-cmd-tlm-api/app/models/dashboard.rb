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

  # What the Dashboards navigator shows for every dashboard, read here so the
  # browser makes one request rather than fetching and parsing each file:
  # [{ 'path', 'title', 'icon', 'color', 'panels' }]. Files that can't be
  # read are left out; the list still names them.
  def self.summaries(scope)
    all(scope).filter_map do |path|
      text = body(scope, path)
      next unless text
      { 'path' => path }.merge(summary(text))
    rescue => e
      OpenC3::Logger.error("Dashboard summary of #{path} failed: #{e.message}", scope: scope)
      nil
    end
  end

  # A light parse of a dashboard's text: the DASHBOARD title, the dashboard's
  # own SETTING ICON / COLOR (before the first PANEL) and the PANEL count.
  # The browser validates the icon and color before using them.
  def self.summary(text)
    result = { 'title' => nil, 'icon' => nil, 'color' => nil, 'panels' => 0 }
    text.to_s.dup.force_encoding('UTF-8').scrub.each_line do |line|
      keyword, rest = line.strip.split(/\s+/, 2)
      next if keyword.nil? || keyword.start_with?('#')
      case keyword.upcase
      when 'DASHBOARD'
        result['title'] ||= unquote(rest)
      when 'PANEL'
        result['panels'] += 1
      when 'SETTING'
        next if result['panels'] > 0
        name, value = rest.to_s.split(/\s+/, 2)
        case name.to_s.upcase
        when 'ICON' then result['icon'] = unquote(value)
        when 'COLOR' then result['color'] = unquote(value)
        end
      end
    end
    result
  end

  # The first parameter, without its quotes
  def self.unquote(text)
    text = text.to_s.strip
    match = text.match(/\A"([^"]*)"|\A'([^']*)'/)
    return match[1] || match[2] if match
    text.split(/\s+/)[0]
  end
  private_class_method :unquote

  # The file a dashboard lives in. Filenames are lowercase. Also the name
  # Enterprise version history tracks it by, so it's validated here (raising
  # ArgumentError) before it reaches the bucket or git.
  def self.path(target, dashboard)
    path = "#{target}/dashboards/#{strip_modified(dashboard).downcase}.txt"
    validate_name(path)
    path
  end

  def self.find(scope, target, dashboard)
    body(scope, path(target, dashboard))
  end

  def self.create(scope, target, dashboard, text)
    super(scope, path(target, dashboard), text)
  end

  def self.destroy(scope, target, dashboard)
    super(scope, path(target, dashboard))
  end
end
