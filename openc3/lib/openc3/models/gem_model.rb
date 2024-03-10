# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'fileutils'
require 'open-uri'
require 'nokogiri'
require 'rubygems'
require 'rubygems/uninstaller'
require 'tempfile'
require 'openc3/utilities/process_manager'
require 'openc3/api/api'
require 'pathname'

module OpenC3
  # This class acts like a Model but doesn't inherit from Model because it doesn't
  # actual interact with the Store (Redis). Instead we implement names, get, put
  # and destroy to allow interaction with gem files from the PluginModel and
  # the GemsController.
  class GemModel
    include Api

    def self.names
      if Dir.exist?("#{ENV['GEM_HOME']}/gems")
        result = Pathname.new("#{ENV['GEM_HOME']}/gems").children.select { |c| c.directory? }.collect { |p| File.basename(p) + '.gem' }
      else
        result = []
      end
      return result.sort
    end

    def self.get(name)
      path = "#{ENV['GEM_HOME']}/cosmoscache/#{name}"
      return path if File.exist?(path)
      path = "#{ENV['GEM_HOME']}/cache/#{name}"
      return path if File.exist?(path)
      raise "Gem #{name} not found"
    end

    def self.put(gem_file_path, gem_install: true, scope:)
      if File.file?(gem_file_path)
        gem_filename = File.basename(gem_file_path)
        # Put into cosmoscache folder that we control
        FileUtils.mkdir_p("#{ENV['GEM_HOME']}/cosmoscache") unless Dir.exist?("#{ENV['GEM_HOME']}/cosmoscache")
        FileUtils.cp(gem_file_path, "#{ENV['GEM_HOME']}/cosmoscache/#{File.basename(gem_file_path)}")
        if gem_install
          Logger.info "Installing gem: #{gem_filename}"
          result = OpenC3::ProcessManager.instance.spawn(["ruby", "/openc3/bin/openc3cli", "geminstall", gem_filename, scope], "package_install", gem_filename, Time.now + 3600.0, scope: scope)
          return result.name
        end
      else
        message = "Gem file #{gem_file_path} does not exist!"
        Logger.error message
        raise message
      end
      return nil
    end

    def self.install(name_or_path, scope:)
      if File.exist?(name_or_path)
        gem_file_path = name_or_path
      else
        gem_file_path = get(name_or_path)
      end
      begin
        rubygems_url = get_setting('rubygems_url', scope: scope)
      rescue
        # If Redis isn't running try the ENV, then simply rubygems.org
        rubygems_url = ENV['RUBYGEMS_URL']
        rubygems_url ||= 'https://rubygems.org'
      end
      Gem.sources = [rubygems_url] if rubygems_url
      Gem.done_installing_hooks.clear
      begin
        # Look for local gems only first, this avoids lengthly timeouts when checking rubygems in airgap env
        Gem.install(gem_file_path, "> 0.pre", build_args: ['--no-document'], prerelease: true, domain: :local)
      rescue Gem::Exception => err
        # If there is a failure look for both local and remote gems
        Gem.install(gem_file_path, "> 0.pre", build_args: ['--no-document'], prerelease: true, domain: :both)
      end
    rescue => err
      message = "Gem file #{gem_file_path} error installing to #{ENV['GEM_HOME']}\n#{err.formatted}"
      Logger.error message
      raise err
    end

    def self.destroy(name, log_and_raise_needed_errors: true)
      gem_name, version = self.extract_name_and_version(name)
      plugin_gem_names = PluginModel.gem_names
      if plugin_gem_names.include?(name)
        if log_and_raise_needed_errors
          message = "Gem file #{name} can't be uninstalled because needed by installed plugin"
          Logger.error message
          raise message
        end
      else
        begin
          Gem::Uninstaller.new(gem_name, {:version => version, :force => true}).uninstall
        rescue => err
          Logger.error "Gem file #{name} error uninstalling\n#{err.formatted}"
          raise err
        end
      end
    end

    def self.extract_name_and_version(name)
      split_name = name.split('-')
      gem_name = split_name[0..-2].join('-')
      version = File.basename(split_name[-1], '.gem')
      return gem_name, version
    end

    def self.destroy_all_other_versions(name)
      keep_gem_name, keep_gem_version = GemModel.extract_name_and_version(name)
      GemModel.names.each do |gem_full_name|
        gem_name, gem_version = GemModel.extract_name_and_version(gem_full_name)
        if gem_name == keep_gem_name and gem_version != keep_gem_version
          GemModel.destroy(gem_full_name, log_and_raise_needed_errors: false)
        end
      end
    end
  end
end
