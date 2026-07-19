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
require 'openc3/models/microservice_model'
require 'openc3/models/scope_model'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/utilities/secrets'

# View of the Iroh bridges (hubs), plus create/delete and manual-enrollment
# token generation. A bridge is a `bridge_microservice` (the Iroh hub) whose
# identity/ticket the running hub records in a BridgeModel; this controller
# creates/removes that microservice (and its identity) and mints one-time
# enrollment tokens for pairing a remote openc3-app.
class BridgesController < ModelController
  def initialize
    super()
    @model_class = OpenC3::BridgeModel
  end

  # POST /bridges — create a new bridge: deploy its bridge_microservice (the Iroh
  # hub), which generates the bridge's identity and ticket on startup.
  def create(update_model = false)
    return unless authorization('admin')
    name = params[:name].to_s.strip.upcase
    if name.empty?
      render json: { status: 'error', message: 'Bridge name is required' }, status: :bad_request
      return
    end
    unless name =~ /\A[A-Z0-9_]+\z/
      render json: { status: 'error', message: 'Bridge name must contain only letters, numbers, and underscores' }, status: :bad_request
      return
    end
    microservice_name = "#{params[:scope]}__BRIDGE__#{name}"
    if OpenC3::MicroserviceModel.get_model(name: microservice_name, scope: params[:scope])
      render json: { status: 'error', message: "Bridge '#{name}' already exists" }, status: :conflict
      return
    end
    shard = OpenC3::ScopeModel.get_model(name: params[:scope])&.shard || 0
    OpenC3::BridgeModel.build_microservice(bridge_name: name, scope: params[:scope], shard: shard).create
    OpenC3::Logger.info("Bridge created: #{name}", scope: params[:scope], user: username())
    head :ok
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end

  # DELETE /bridges/:id — delete a bridge: stop and remove its hub microservice,
  # its identity record, and its stored private key.
  def destroy
    return unless authorization('admin')
    name = params[:id].to_s.upcase
    scope = params[:scope]
    # Guard: refuse to delete a bridge that interfaces/routers still route
    # through (they dial the hub by name and would break).
    users = bridge_references(name, scope)
    unless users.empty?
      render json: {
        status: 'error',
        message: "Bridge '#{name}' is in use by: #{users.join(', ')}. Remove or re-point them before deleting the bridge.",
      }, status: :conflict
      return
    end
    # Removing the microservice model makes the operator stop the running hub.
    microservice = OpenC3::MicroserviceModel.get_model(name: "#{scope}__BRIDGE__#{name}", scope: scope)
    microservice.destroy if microservice
    # Remove the bridge identity/ticket record.
    bridge = @model_class.get_model(name: name, scope: scope)
    bridge.destroy if bridge
    # Remove the stored private key (may not exist if the hub never started).
    begin
      OpenC3::Secrets.getClient.delete("BRIDGE_#{name}_PRIVATE_KEY", scope: scope)
    rescue StandardError
      # ignore: nothing to delete
    end
    OpenC3::Logger.info("Bridge destroyed: #{name}", scope: scope, user: username())
    head :ok
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end

  # POST /bridges/:id/token — generate a one-time manual-enrollment token for
  # the named bridge (used to pair a remote openc3-app that can't auto-enroll
  # over the local Docker control plane).
  def token
    return unless authorization('admin')
    model = @model_class.get_model(name: params[:id], scope: params[:scope])
    if model.nil?
      render json: { status: 'error', message: "Bridge '#{params[:id]}' not found" }, status: :not_found
      return
    end
    begin
      token = model.generate_enrollment_token
      OpenC3::Logger.info("Generated enrollment token for bridge #{params[:id]}", scope: params[:scope], user: username())
      render json: { token: token }
    rescue => error
      render json: { status: 'error', message: error.message }, status: :bad_request
    end
  end

  private

  # Names of the interfaces and routers (in `scope`) that route through the
  # bridge named `name` (compared case-insensitively, as bridge names are
  # canonicalized to uppercase).
  def bridge_references(name, scope)
    users = []
    [OpenC3::InterfaceModel, OpenC3::RouterModel].each do |klass|
      klass.all(scope: scope).each do |item_name, item|
        users << item_name if item['bridge_name'].to_s.upcase == name
      end
    end
    users
  end
end
