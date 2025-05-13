# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

spec = Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-accessor-test'
  s.summary = 'OpenC3 COSMOS Accessor Example Plugin'
  s.description = <<-EOF
  This plugin is used to provide examples of using different accessors
  EOF
  s.authors = ['Ryan Melton', 'Jason Thomas']
  s.email = ['ryan@openc3.com', 'jason@openc3.com']
  s.homepage = 'https://github.com/OpenC3/cosmos'

  s.platform = Gem::Platform::RUBY

  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.licenses = ['AGPL-3.0-only', 'Nonstandard']

  s.files = Dir.glob("{targets,lib,tools,microservices}/**/*") + %w(Rakefile LICENSE.txt README.md plugin.txt)
end
