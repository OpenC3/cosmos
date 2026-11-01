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

$openc3_scope = ARGV[0]

require 'json'

# Read the one-line auth JSON the parent wrote to stdin right after spawn.
# Applied at runtime so the secret is never in the process environment.
begin
  stdin_creds = JSON.parse($stdin.gets.to_s)
  auth = stdin_creds['auth']
  raise 'no auth' unless auth.is_a?(Hash)
rescue StandardError
  raise "run_suite_analysis: missing or malformed stdin credentials"
end
if auth['token'].to_s.strip != ''
  ENV['OPENC3_API_TOKEN'] = auth['token']
else
  # Leave OPENC3_API_USER unset for a null username: an empty string is not nil,
  # so ServerProxy would select Keycloak auth instead of Core auth.
  ENV['OPENC3_API_USER'] = auth['user'] if auth['user']
  if auth['password']
    ENV['OPENC3_API_PASSWORD'] = auth['password']
    # Core authenticates as the service; OpenC3Authentication sets @service by
    # comparing OPENC3_API_PASSWORD to OPENC3_SERVICE_PASSWORD, so restore it.
    ENV['OPENC3_SERVICE_PASSWORD'] = auth['password']
  end
end

require 'openc3'
require 'openc3/script/suite_runner'
require 'openc3/utilities/running_script'

# The API client has authenticated during the requires above; clear the
# passwords before loading user code so it can't read them.
ENV['OPENC3_API_PASSWORD'] = nil
ENV['OPENC3_SERVICE_PASSWORD'] = nil

require ARGV[1]

puts OpenC3::SuiteRunner.build_suites.as_json().to_json(allow_nan: true)
