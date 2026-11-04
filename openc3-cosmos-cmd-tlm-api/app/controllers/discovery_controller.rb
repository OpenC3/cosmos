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

require 'openc3/models/bridge_model'
require 'openc3/models/plugin_model'
require 'openc3/topics/discovery_topic'
require 'openc3/utilities/hardware_discovery'

# Runs a Python Discovery class on the host paired with a bridge (via openc3-app)
# and returns what it found, e.g. the serial ports for a VARIABLE_DISCOVERY.
class DiscoveryController < ApplicationController
  DISCOVERY_TIMEOUT_S = 15

  # POST /discovery { bridge: 'DEFAULT', discovery: ['openc3/discovery/serial_discovery.py', ...], exclude_plugin: 'name' }
  # Returns { results: [{ value, text }], claimed: [{ value, text, plugin }] } where claimed are
  # the discovered values already claimed by other installed plugins (see PluginModel.discovery_claims).
  # exclude_plugin is the plugin being upgraded or edited, whose own claims don't count.
  def create
    # Discovery executes code on the host so restrict it like plugin installs
    return unless authorization('admin')
    discovery = params[:discovery]
    unless discovery.is_a?(Array) and !discovery.empty?
      render json: { status: 'error', message: 'discovery must be a list of the discovery class filename and its parameters' }, status: :bad_request
      return
    end
    bridge_name = (params[:bridge].presence || 'DEFAULT').to_s.upcase
    bridge = OpenC3::BridgeModel.get_model(name: bridge_name, scope: params[:scope])
    unless bridge and bridge.app_public_key
      render json: { status: 'error', message: "Bridge '#{bridge_name}' is not paired with openc3-app" }, status: :service_unavailable
      return
    end
    discovery = discovery.map(&:to_s)
    results = OpenC3::DiscoveryTopic.discover(bridge_name, discovery, timeout: DISCOVERY_TIMEOUT_S, scope: params[:scope])
    claims = OpenC3::PluginModel.discovery_claims(bridge_name, discovery[0], exclude_plugin: params[:exclude_plugin].presence, scope: params[:scope])
    available, claimed = results.partition { |result| !claims.key?(result['value'].to_s) }
    render json: text_json({ 'results' => available, 'claimed' => claimed.map { |result| result.merge('plugin' => claims[result['value'].to_s]) } })
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end

  # POST /discovery/scan { bridge: 'DEFAULT' | 'ALL' }
  # Scans the host of the bridge (or of every paired bridge) for hardware and
  # proposes plugins to install for the devices found (see OpenC3::HardwareDiscovery)
  def scan
    return unless authorization('admin')
    result = OpenC3::HardwareDiscovery.scan(bridge: params[:bridge].presence || 'DEFAULT', scope: params[:scope])
    render json: text_json(result)
  rescue StandardError => error
    status = error.message.include?('not paired') ? :service_unavailable : :internal_server_error
    render json: { status: 'error', message: error.message }, status: status
    logger.error(error.formatted) if status == :internal_server_error
  end

  private

  # Device names and plugin titles are text, like "Manette 🎮", which the
  # COSMOS String#as_json would send as raw bytes outside the Latin-1 range
  def text_json(value)
    JSON.generate(value)
  end
end
