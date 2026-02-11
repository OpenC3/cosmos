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

begin
  require 'rspec/core/rake_task'

  desc 'Run all specs with basic output'
  RSpec::Core::RakeTask.new do |t|
    # Use ** to recursively find specs in all subdirectories (spec/utilities/, spec/models/, etc.)
    t.pattern = ['spec/**/*_spec.rb']
    t.rspec_opts = '-f d --warnings'
  end
rescue LoadError
  puts "rspec not loaded. gem install rspec"
end
