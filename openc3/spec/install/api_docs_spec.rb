# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'find'

module OpenC3
  describe OpenC3 do
    DEPRECATED_APIS = %w(require_utility check_tolerance_raw wait_raw wait_check_raw wait_tolerance_raw wait_check_tolerance_raw)
    DEPRECATED_APIS.concat(%w(tlm_variable save_setting))
    # These are only internal APIs
    IGNORED_APIS = %w(method_missing self.included write puts openc3_script_sleep)
    IGNORED_APIS.concat(%w(running_script_backtrace running_script_debug running_script_prompt update_news update_plugin_store))
    IGNORED_APIS.concat(%w(package_install package_uninstall package_status package_download))
    IGNORED_APIS.concat(%w(plugin_install_phase1 plugin_install_phase2 plugin_update_phase1 plugin_uninstall plugin_status))

    def parse_file(filename, methods)
      File.open(filename) do |file|
        data = file.read
        lines = data.split("\n")
        # Check for our API indicator and strip out the excess
        if data.include?("START PUBLIC API")
          start = 0
          end_line = -1
          lines.each_with_index do |line, index|
            start = index if line.include?("START PUBLIC API")
            end_line = index if line.include?("END PUBLIC API")
          end
          lines = lines[start..end_line]
        end
        lines.each do |line|
          if line.strip =~ /^def /
            next if line.include?('def _')
            next if line.include?('initialize') and not line.include?('initialize_')
            method = line.strip.split(' ')[1]
            if method.include?('(')
              methods[method.split('(')[0]] = filename
            else
              methods[method] = filename
            end
          end
        end
      end
    end

    def ruby_api
      ruby_api = {}
      Dir[File.join(SPEC_DIR,'../lib/openc3/script/*.rb')].each do |filename|
        next if filename.include?('extract')
        next if filename.include?('web_socket_api')
        next if filename.include?('suite_results')
        next if filename.include?('suite_runner')
        parse_file(filename, ruby_api)
      end
      Dir[File.join(SPEC_DIR,'../lib/openc3/api/*.rb')].each do |filename|
        next if filename.include?('metrics_api') # TODO: document and implement Python equivalent
        parse_file(filename, ruby_api)
      end
      return ruby_api
    end

    def python_api
      python_api = {}
      Dir[File.join(SPEC_DIR,'../python/openc3/script/*.py')].each do |filename|
        next if filename.include?('authorization')
        next if filename.include?('decorators')
        next if filename.include?('server_proxy')
        next if filename.include?('stream')
        next if filename.include?('web_socket_api')
        next if filename.include?('suite_results')
        next if filename.include?('suite_runner')
        parse_file(filename, python_api)
      end
      Dir[File.join(SPEC_DIR,'../python/openc3/api/*.py')].each do |filename|
        parse_file(filename, python_api)
      end
      return python_api
    end

    def documented
      documented = []
      File.open(File.join(SPEC_DIR,'../../docs.openc3.com/docs/guides/scripting-api.md')) do |file|
        apis = false
        file.each do |line|
          if line.strip.include?('###')
            if line.include?("Migration")
              apis = true
              next
            end
            next unless apis
            line = line.strip[4..-1]
            if line.include?(",") # Split lines like '### check, check_raw'
              line.split(',').each do |method|
                documented << method.strip
              end
            else
              documented << line
            end
          end
        end
      end
      return documented.uniq!
    end

    before(:all) do
      @ruby_api = ruby_api()
      @python_api = python_api()
      @documented = documented()
    end

    it "should document all Ruby APIs" do
      undocumented = @ruby_api.keys - @documented - DEPRECATED_APIS - IGNORED_APIS
      expect(undocumented).to be_empty, "Following Ruby APIs not documented: #{undocumented}"
    end

    it "should document all Python APIs" do
      undocumented = @python_api.keys - @documented - DEPRECATED_APIS - IGNORED_APIS
      expect(undocumented).to be_empty, "Following Python APIs not documented: #{undocumented}"
    end

    it "should not have extra documentation" do
      extra = @documented - @ruby_api.keys - @python_api.keys
      expect(extra).to be_empty, "Documented in scripting-api.md but not in source: #{extra}"
    end

    it "should have Ruby / Python parity" do
      ruby_api_massaged = []
      @ruby_api.keys.each do |key|
        # Remove ? and ! from method names as python can't use them
        if key.include?('?') or key.include?('!')
          ruby_api_massaged << key[0..-2]
        else
          ruby_api_massaged << key
        end
      end
      ruby_not_python = ruby_api_massaged - @python_api.keys - DEPRECATED_APIS - IGNORED_APIS
      expect(ruby_not_python).to be_empty, "APIs found in Ruby but not Python: #{ruby_not_python}"
      python_not_ruby = @python_api.keys - ruby_api_massaged - DEPRECATED_APIS - IGNORED_APIS
      expect(python_not_ruby).to be_empty, "APIs found in Python but not Ruby: #{python_not_ruby}"
    end
  end
end
