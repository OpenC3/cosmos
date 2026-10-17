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
require 'openc3/topics/discovery_topic'

# Runs a Python Discovery class on the host paired with a bridge (via openc3-app)
# and returns what it found, e.g. the serial ports for a VARIABLE_DISCOVERY.
class DiscoveryController < ApplicationController
  DISCOVERY_TIMEOUT_S = 15

  # POST /discovery { bridge: 'DEFAULT', discovery: ['openc3/discovery/serial_discovery.py', ...] }
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
    results = OpenC3::DiscoveryTopic.discover(bridge_name, discovery.map(&:to_s), timeout: DISCOVERY_TIMEOUT_S, scope: params[:scope])
    render json: results
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end
end
