# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require 'spec_helper'

# Regression test for the stdin-credential ordering bug.
#
# The spawned runner scripts receive their API credentials over stdin (so the
# token never lands in /proc/<pid>/environ) and apply them to the process
# environment at runtime. Those credentials MUST be applied BEFORE the openc3
# library is loaded, because:
#   - Python openc3.environment freezes OPENC3_API_TOKEN / OPENC3_API_USER as
#     module constants at import, and ApiServerProxy() picks its auth strategy
#     at construction (which happens at import of openc3.script).
#   - Ruby builds $api_server (via include OpenC3::Script -> initialize_script)
#     when the openc3 script support is required, reading ENV at that point.
#
# If the credentials are applied AFTER the library loads, the API client is
# built with no token and every API call fails server-side with
# "AuthError: Token is nil". This test fails without the fix (credentials below
# the first openc3 load) and passes with it.
RSpec.describe 'runner script credential/import ordering' do
  SCRIPTS_DIR = File.expand_path('../../scripts', __dir__)

  # [file, credential-assignment regex, openc3-load regex]
  RUBY_CRED = /(?:ENV\['OPENC3_API_TOKEN'\])\s*=/
  RUBY_LOAD = /^\s*require\s+['"]openc3/
  PY_CRED   = /os\.environ\["OPENC3_API_TOKEN"\]\s*=/
  PY_LOAD   = /^\s*(?:import\s+openc3|from\s+openc3)/

  {
    'run_script.rb'          => [RUBY_CRED, RUBY_LOAD],
    'run_suite_analysis.rb'  => [RUBY_CRED, RUBY_LOAD],
    'run_script.py'          => [PY_CRED, PY_LOAD],
    'run_suite_analysis.py'  => [PY_CRED, PY_LOAD],
  }.each do |filename, (cred_re, load_re)|
    it "#{filename} applies API credentials before loading openc3" do
      path = File.join(SCRIPTS_DIR, filename)
      lines = File.read(path).lines
      cred_line = lines.index { |l| l =~ cred_re }
      load_line = lines.index { |l| l =~ load_re }

      expect(cred_line).not_to be_nil, "#{filename}: no OPENC3_API_TOKEN assignment found"
      expect(load_line).not_to be_nil, "#{filename}: no openc3 load found"
      expect(cred_line).to be < load_line,
        "#{filename}: credentials applied on line #{cred_line + 1} but openc3 is loaded " \
        "first on line #{load_line + 1}; the API client will capture a nil token"
    end
  end

  # C1 regression: a null username must stay unset. Coercing it to "" makes it
  # non-nil, so ServerProxy / ApiServerProxy.generate_auth selects Keycloak auth
  # and breaks Core (which authenticates by password).
  it "never coerces a null OPENC3_API_USER to an empty string" do
    %w[run_script.rb run_suite_analysis.rb].each do |f|
      expect(File.read(File.join(SCRIPTS_DIR, f))).not_to include("auth['user'].to_s"),
        "#{f}: coerces a null username to \"\" which selects Keycloak over Core auth"
    end
    %w[run_script.py run_suite_analysis.py].each do |f|
      expect(File.read(File.join(SCRIPTS_DIR, f))).not_to include('auth.get("user") or ""'),
        "#{f}: coerces a null username to \"\" which selects Keycloak over Core auth"
    end
  end

  # C2 regression: Core's OpenC3Authentication sets its service flag by comparing
  # OPENC3_API_PASSWORD to OPENC3_SERVICE_PASSWORD; the latter is scrubbed from the
  # child env, so each runner must restore it from the delivered password or Core
  # scripts post to auth/verify instead of auth/verify_service and fail.
  {
    'run_script.rb'         => "ENV['OPENC3_SERVICE_PASSWORD'] = auth['password']",
    'run_suite_analysis.rb' => "ENV['OPENC3_SERVICE_PASSWORD'] = auth['password']",
    'run_script.py'         => 'os.environ["OPENC3_SERVICE_PASSWORD"] = auth["password"]',
    'run_suite_analysis.py' => 'os.environ["OPENC3_SERVICE_PASSWORD"] = auth["password"]',
  }.each do |filename, snippet|
    it "#{filename} restores OPENC3_SERVICE_PASSWORD for Core service authentication" do
      expect(File.read(File.join(SCRIPTS_DIR, filename))).to include(snippet)
    end
  end

  # The passwords must be removed from the environment after openc3 loads (the API
  # client has authenticated by then) and before user code runs, or a script that
  # prints its environment exposes them (playwright "does not expose secrets").
  RUBY_CLEAR = /^\s*OpenC3::ScriptEnv\.clear_credentials\b/
  PY_CLEAR   = /^\s*clear_credentials\(\)/
  {
    'run_script.rb'         => [RUBY_LOAD, RUBY_CLEAR, /^\s*running_script\s*=\s*RunningScript\.new/],
    'run_suite_analysis.rb' => [RUBY_LOAD, RUBY_CLEAR, /^\s*require\s+ARGV\[1\]/],
    'run_script.py'         => [PY_LOAD, PY_CLEAR, /^\s*running_script\s*=\s*RunningScript\(/],
    'run_suite_analysis.py' => [PY_LOAD, PY_CLEAR, /^exec\(data/],
  }.each do |filename, (load_re, clear_re, user_code_re)|
    it "#{filename} clears credentials after loading openc3 and before running user code" do
      lines = File.read(File.join(SCRIPTS_DIR, filename)).lines
      load_line = lines.index { |l| l =~ load_re }
      clear_line = lines.index { |l| l =~ clear_re }
      user_line = lines.index { |l| l =~ user_code_re }
      expect(clear_line).not_to be_nil, "#{filename}: credentials are never cleared from the environment"
      expect(user_line).not_to be_nil, "#{filename}: user code entry point not found"
      expect(clear_line).to be > load_line, "#{filename}: credentials cleared before openc3 loads; auth will fail"
      expect(clear_line).to be < user_line, "#{filename}: credentials cleared after user code can read them"
    end
  end

  it "clears the stdin-applied API passwords in both languages" do
    lib = File.expand_path('../../../openc3', __dir__)
    rb = File.read(File.join(lib, 'lib/openc3/utilities/script_env.rb'))
    py = File.read(File.join(lib, 'python/openc3/utilities/script_env.py'))
    expect(rb[/CLEARED_VARS = \[.*?\]/m]).to include("'OPENC3_API_PASSWORD'", "'OPENC3_SERVICE_PASSWORD'")
    expect(py[/CLEARED_VARS = \[.*?\]/m]).to include('"OPENC3_API_PASSWORD"', '"OPENC3_SERVICE_PASSWORD"')
  end
end
