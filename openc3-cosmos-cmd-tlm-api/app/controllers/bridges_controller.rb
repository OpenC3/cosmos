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

# Read-only view of the Iroh bridges (hubs) plus manual-enrollment token
# generation. Bridges themselves are created/maintained by their
# bridge_microservice; this controller only surfaces them to the Admin Bridges
# page and mints one-time enrollment tokens for pairing a remote openc3-app.
class BridgesController < ModelController
  def initialize
    super()
    @model_class = OpenC3::BridgeModel
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
end
