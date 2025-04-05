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
    IGNORED_INTERFACES = %w(__init__ interface simulated_target_interface stream_interface)
    # The following are plugin interfaces are expected to be documented but don't exist in the source
    PLUGIN_INTERFACES = %w(snmp_interface snmp_trap_interface grpc_interface)
    # When python serial interface is implemented, remove this from the list
    PYTHON_TODO_INTERFACES = %w(serial_interface)
    def documented
      documented = []
      File.open(File.join(SPEC_DIR,'../../docs.openc3.com/docs/configuration/interfaces.md')) do |file|
        file.each do |line|
          if line.strip =~ /^INTERFACE /
            part = line.strip.split()[2].split('/')[-1].split('.')[0]
            documented << part
          end
        end
      end
      return documented.uniq!
    end

    before(:all) do
      @ruby_interfaces = Dir[File.join(SPEC_DIR,'../lib/openc3/interfaces/*.rb')].map { |f| File.basename(f, '.rb') }
      @python_interfaces = Dir[File.join(SPEC_DIR,'../python/openc3/interfaces/*.py')].map { |f| File.basename(f, '.py') }
      @documented = documented()
    end

    it "interfaces.rb should include all Ruby interfaces" do
      included = []
      File.open(File.join(SPEC_DIR,'../lib/openc3/interfaces.rb')) do |file|
        file.each do |line|
          if line.include?('interface.rb')
            # Parsing a line like: autoload(:HttpClientInterface, 'openc3/interfaces/http_client_interface.rb')
            included << line.strip.split()[1].split('/')[-1].split('.')[0]
          end
        end
      end
      not_included = @ruby_interfaces - included
      expect(not_included).to be_empty, "Following Ruby interfaces not in openc3/interfaces.rb: #{not_included}"
      extra = included - @ruby_interfaces
      expect(extra).to be_empty, "Following Ruby interfaces in openc3/interfaces.rb but do not exist: #{extra}"
    end

    it "should document all Ruby interfaces" do
      undocumented = @ruby_interfaces - @documented - IGNORED_INTERFACES
      expect(undocumented).to be_empty, "Following Ruby interfaces not documented: #{undocumented}"
    end

    it "should document all Python interfaces" do
      undocumented = @python_interfaces - @documented - IGNORED_INTERFACES
      expect(undocumented).to be_empty, "Following Python interfaces not documented: #{undocumented}"
    end

    it "should not have extra documentation" do
      extra = @documented - @ruby_interfaces - @python_interfaces - IGNORED_INTERFACES - PLUGIN_INTERFACES
      expect(extra).to be_empty, "Documented in interfaces.md but not in source: #{extra}"
    end

    it "should have Ruby / Python parity" do
      ruby_not_python = @ruby_interfaces - @python_interfaces - PYTHON_TODO_INTERFACES
      expect(ruby_not_python).to be_empty, "Interfaces found in Ruby but not Python: #{ruby_not_python}"
      python_not_ruby = @python_interfaces - @ruby_interfaces - %w(__init__)
      expect(python_not_ruby).to be_empty, "Interfaces found in Python but not Ruby: #{python_not_ruby}"
    end
  end
end
