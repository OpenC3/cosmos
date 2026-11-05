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

require 'spec_helper'
require 'stringio'

module OpenC3
  describe 'openc3cli plugin updates' do
    before(:all) do
      original_argv = ARGV.dup
      original_stdout = $stdout
      ARGV.replace([])
      $stdout = StringIO.new
      load File.expand_path('../../bin/openc3cli', __dir__)
    ensure
      ARGV.replace(original_argv)
      $stdout = original_stdout
    end

    it 'propagates a failed enforced rollback after an enforced upgrade failure' do
      plugin_model = instance_double(PluginModel, variables: {}, destroyed?: true)
      updated_plugin_hash = { 'name' => 'UPDATED__0', 'variables' => {}, 'plugin_txt_lines' => [] }

      expect(PluginModel).to receive(:get_model).with(name: 'PREVIOUS__0', scope: 'DEFAULT').and_return(plugin_model)
      expect(plugin_model).to receive(:destroy).ordered
      expect(PluginModel).to receive(:install_phase1).ordered.and_return(updated_plugin_hash)
      expect(PluginModel).to receive(:install_phase2)
        .with(updated_plugin_hash, scope: 'DEFAULT', enforce_dependencies: true)
        .ordered
        .and_raise('updated plugin dependencies failed')
      expect(plugin_model).to receive(:restore).with(enforce_dependencies: true).ordered.and_raise('previous plugin dependencies failed')

      expect {
        update_plugin('updated-1.0.0.gem', 'UPDATED__0', scope: 'DEFAULT', existing_plugin_name: 'PREVIOUS__0', force: true, enforce_dependencies: true)
      }.to raise_error(/failed to restore the previous plugin/i)
    end

    it 'parses variables before trailing load flags' do
      parsed = parse_load_arguments(['plugin.gem', '--variables', 'force', 'enforce_dependencies', 'plugin_hash.json', 'force'])

      expect(parsed).to eq(
        plugin_file_path: 'plugin.gem',
        scope: 'enforce_dependencies',
        plugin_hash_file: 'plugin_hash.json',
        variables_file: 'force',
        force: true,
        enforce_dependencies: false
      )
    end

    it 'treats a trailing enforcement token as a flag but preserves it as a scope before a hash' do
      expect(parse_load_arguments(['plugin.gem', 'enforce_dependencies'])).to include(
        scope: nil,
        enforce_dependencies: true
      )
      expect(parse_load_arguments(['plugin.gem', 'enforce_dependencies', 'plugin_hash.json'])).to include(
        scope: 'enforce_dependencies',
        plugin_hash_file: 'plugin_hash.json',
        enforce_dependencies: false
      )
    end
  end
end
