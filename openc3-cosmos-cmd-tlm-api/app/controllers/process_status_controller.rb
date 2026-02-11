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

require 'openc3/models/process_status_model'

class ProcessStatusController < ModelController
  def initialize
    @model_class = OpenC3::ProcessStatusModel
  end

  def show
    return unless authorization('system')
    if params[:id].downcase == 'all'
      render json: @model_class.all(scope: params[:scope])
    elsif params[:id].split('__').length > 1
      render json: @model_class.get(name: params[:id], scope: params[:scope])
    else
      render json: @model_class.filter("process_type", params[:id], scope: params[:scope], substr: params[:substr])
    end
  end
end
