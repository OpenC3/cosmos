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

# Create the overall gemspec
spec = Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-demo'
  s.summary = 'OpenC3 COSMOS Demo Targets'
  s.description = <<-EOF
    This plugin adds the OpenC3 COSMOS demo configuration to a base OpenC3 COSMOS installation.
    Install this to experiment with a configured OpenC3 COSMOS system.
  EOF
  s.authors = ['Ryan Melton', 'Jason Thomas']
  s.email = ['ryan@openc3.com', 'jason@openc3.com']
  s.homepage = 'https://github.com/OpenC3/cosmos'

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 3.0'

  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.license = "OpenC3"

  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile LICENSE.md README.md plugin.txt requirements.txt)

  s.metadata = {
    "openc3_store_title" => "Demo",
    "openc3_store_description" => "The demo plugin that comes with a fresh COSMOS install",
    "openc3_store_keywords" => "demo, training, testing",
    "openc3_cosmos_minimum_version" => "6.10.4"
  }
end
