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

require 'json'
require 'openc3/models/bridge_model'
require 'openc3/models/gem_model'
require 'openc3/models/plugin_model'
require 'openc3/models/plugin_store_model'
require 'openc3/topics/discovery_topic'

module OpenC3
  # Hardware discovery scans the hosts connected through bridges for devices and
  # proposes plugins to install for them. Plugins are matched by the hardware
  # their plugin.txt can discover (PluginModel.discovery_matchers): plugins in
  # the OpenC3 Store, which computes their matchers when they're uploaded, and
  # plugins already installed in COSMOS, which can be installed again for
  # another device.
  module HardwareDiscovery
    # Seconds to wait for a host to scan. Scanning takes about 10s.
    SCAN_TIMEOUT_S = 40

    # Matchers of installed plugin gems by gem filename. Gem files don't change
    # once uploaded so this only grows with new versions.
    @gem_matchers = {}
    @gem_matchers_mutex = Mutex.new

    # Scan the host of one bridge, or every paired bridge with 'ALL', and
    # propose plugins for the devices found
    #
    # @return [Hash] 'devices' found with their 'candidates' (plugins to
    #   install), 'errors' scanning, the number of matchers 'skipped' and
    #   whether the OpenC3 Store provided any matchers ('store_matchers')
    def self.scan(bridge: 'DEFAULT', scope:)
      sources = plugin_sources(scope: scope)
      matchers, candidates_by_id = unique_matchers(sources)
      bridges = bridge_names(bridge, scope: scope)
      if bridges.empty?
        raise "No bridge is paired with openc3-app" if bridge.to_s.upcase == 'ALL'
        raise "Bridge '#{bridge.to_s.upcase}' is not paired with openc3-app"
      end

      results = {}
      bridges.map do |bridge_name|
        Thread.new do
          results[bridge_name] = DiscoveryTopic.scan(bridge_name, { 'matchers' => matchers }, timeout: SCAN_TIMEOUT_S, scope: scope)
        rescue => error
          results[bridge_name] = { 'error' => error.message }
        end
      end.each(&:join)

      devices = []
      errors = []
      skipped = 0
      bridges.each do |bridge_name|
        result = results[bridge_name]
        if result['error']
          errors << { 'bridge' => bridge_name, 'message' => result['error'] }
          next
        end
        (result['errors'] || {}).each do |discovery_class, message|
          errors << { 'bridge' => bridge_name, 'class' => discovery_class, 'message' => message }
        end
        skipped += (result['skipped'] || {}).length
        claims = Hash.new do |hash, discovery_class|
          hash[discovery_class] = PluginModel.discovery_claims(bridge_name, discovery_class, scope: scope)
        end
        (result['devices'] || []).each do |device|
          devices << device_proposal(bridge_name, device, candidates_by_id, claims)
        end
      end
      {
        'devices' => devices,
        'errors' => errors,
        'skipped' => skipped,
        'store_matchers' => sources.any? { |source| source['source'] == 'store' and !source['matchers'].empty? },
      }
    end

    # The plugins that can be proposed, each with its matchers: OpenC3 Store
    # plugins with discovery data, then installed plugins not already offered
    # by the store
    def self.plugin_sources(scope:)
      installed = PluginModel.all(scope: scope)
      installed_gems = installed.keys.map { |name| name.split('__')[0] }.uniq
      installed_names = installed_gems.map { |gem| gem_name(gem) }
      installed_store_ids = installed.values.map { |plugin| plugin['store_plugin_id'] }.compact

      sources = []
      store_plugins.each do |plugin|
        matchers = Array(plugin.dig('discovery', 'matchers'))
        next if matchers.empty?
        name = gem_name(plugin['gem_filename'].to_s)
        sources << {
          'source' => 'store',
          'store_id' => plugin['id'],
          'store_version_id' => plugin['current_version_id'],
          'name' => name,
          'title' => plugin['title'],
          'image_url' => plugin['image_url'],
          'entitled' => plugin.fetch('entitled', true) != false,
          'installed' => installed_store_ids.include?(plugin['id']) || installed_names.include?(name),
          'matchers' => matchers,
        }
      end
      store_names = sources.map { |source| source['name'] }
      installed_gems.each do |gem|
        next if store_names.include?(gem_name(gem))
        matchers = gem_discovery_matchers(gem, scope: scope)
        next if matchers.empty?
        sources << {
          'source' => 'installed',
          'gem' => gem,
          'name' => gem_name(gem),
          'title' => gem_name(gem),
          'entitled' => true,
          'installed' => true,
          'matchers' => matchers,
        }
      end
      sources
    end

    # The OpenC3 Store catalog, or none if it can't be read
    def self.store_plugins
      plugins = JSON.parse(PluginStoreModel.all || '[]')
      plugins.is_a?(Array) ? plugins : []
    rescue JSON::ParserError
      []
    end

    # The matchers of an installed plugin gem, from its plugin.txt
    def self.gem_discovery_matchers(gem, scope:)
      @gem_matchers_mutex.synchronize do
        @gem_matchers[gem] ||= begin
          variables = PluginModel.install_phase1(GemModel.get(gem), validate_only: true, scope: scope)['variables']
          # plugin.txt is read as binary but its titles are UTF-8 text, as the store's are
          utf8(PluginModel.discovery_matchers(variables)['matchers'])
        rescue => error
          Logger.warn("Hardware discovery could not read the plugin.txt of #{gem}: #{error.message}", scope: scope)
          []
        end
      end
    end

    # Each distinct discovery (class and parameters) is checked once on the
    # host, though many plugins may use it. Returns the matchers to send and
    # the plugin candidates for each matcher id.
    def self.unique_matchers(sources)
      ids = {}
      candidates_by_id = Hash.new { |hash, id| hash[id] = [] }
      sources.each do |source|
        source['matchers'].each do |matcher|
          key = [PluginModel.discovery_class_key(matcher['class']), Array(matcher['params'])]
          id = (ids[key] ||= (ids.length + 1).to_s)
          candidates_by_id[id] << [source, matcher]
        end
      end
      matchers = ids.map { |(discovery_class, params), id| { 'id' => id, 'class' => discovery_class, 'params' => params } }
      [matchers, candidates_by_id]
    end

    def self.bridge_names(bridge, scope:)
      bridge = bridge.to_s.upcase
      paired = BridgeModel.all(scope: scope).select { |_name, model| model['app_public_key'] }.keys.sort
      return paired if bridge == 'ALL'
      paired.include?(bridge) ? [bridge] : []
    end

    # A device found on a host with the plugins proposed for it, most specific
    # match first
    def self.device_proposal(bridge_name, device, candidates_by_id, claims)
      discovery_class = device['class']
      matched_params = Hash(device['matched_params'])
      candidates = Array(device['matches']).flat_map do |id|
        candidates_by_id[id].map do |source, matcher|
          variables = Hash(matcher['set']).merge(matcher['variable'] => device['value'], PluginModel::BRIDGE_VARIABLE_NAME => bridge_name)
          candidate = source.slice('source', 'store_id', 'store_version_id', 'gem', 'name', 'title', 'image_url', 'entitled', 'installed').compact
          # Rated by the parameters the device matched when the host says
          # which (a matcher's parameters are usually alternatives)
          params = Array(matcher['params'])
          indexes = matched_params[id.to_s]
          params = params.values_at(*indexes).compact if indexes.is_a?(Array) and !indexes.empty?
          candidate.merge(
            'match_title' => matcher['title'],
            'variables' => variables,
            'specificity' => specificity(discovery_class, params),
            'possible' => name_pattern_only?(discovery_class, params),
          )
        end
      end
      # A plugin matched more than once for the device keeps its best match,
      # and matches by a name pattern alone come after the others
      candidates = candidates.sort_by { |candidate| [candidate['possible'] ? 1 : 0, -candidate['specificity'], candidate['title'].to_s.downcase] }
      candidates = candidates.uniq { |candidate| [candidate['source'], candidate['name'], candidate['match_title'], candidate['variables']] }
      {
        'bridge' => bridge_name,
        'class' => discovery_class,
        'value' => device['value'],
        'text' => device['text'],
        'details' => device['details'] || {},
        'claimed_by' => claims[discovery_class][device['value'].to_s],
        'candidates' => candidates,
      }
    end

    # How specifically a matcher identifies hardware, so an exact USB product
    # ranks above a USB serial chip many devices use
    def self.specificity(discovery_class, params)
      case discovery_class.split('.').last
      when 'serial_discovery'
        params.map { |param| param =~ /:[0-9A-Fa-f]+\z/ ? 2 : 1 }.max || 0
      when 'hid_discovery'
        params.count { |param| !%w(0 0x0 nil none).include?(param.to_s.strip.downcase) && !param.to_s.strip.empty? }
      when 'usb_discovery'
        # |-separated conditions where a VID:PID is two (vendor and product)
        params.map { |param| param.split('|').sum { |condition| condition =~ /\A\h+:\h+\z/ ? 2 : 1 } }.max || 0
      else
        # zeroconf, bluetooth, ssdp and neighbor matchers are |-separated conditions
        params.map { |param| param.split('|').length }.max || 0
      end
    end

    # The conditions that only match a device's name, by discovery class
    NAME_CONDITIONS = {
      'bluetooth_discovery' => %w(local_name),
      'neighbor_discovery' => %w(hostname),
      'usb_discovery' => %w(manufacturer product),
      'ssdp_discovery' => %w(friendlyname),
    }

    # Whether a match is only by a name pattern (e.g. a Bluetooth local_name of
    # Govee*), which other devices from the same maker can share, so the plugin
    # may not support the device
    def self.name_pattern_only?(discovery_class, params)
      keys = NAME_CONDITIONS[discovery_class.to_s.split('.').last]
      return false if keys.nil? or params.empty?
      params.all? do |param|
        param.to_s.split('|').all? do |condition|
          key, glob = condition.split('=', 2)
          keys.include?(key.to_s.strip.downcase) and glob.to_s.match?(/[*?\[]/)
        end
      end
    end

    def self.utf8(value)
      case value
      when String then value.dup.force_encoding('UTF-8')
      when Array then value.map { |item| utf8(item) }
      when Hash then value.to_h { |key, item| [utf8(key), utf8(item)] }
      else value
      end
    end

    # A gem's name without its version, e.g. openc3-cosmos-demo
    def self.gem_name(gem_filename)
      File.basename(gem_filename.to_s, '.gem').sub(/-\d[\w.]*\z/, '')
    end
  end
end
