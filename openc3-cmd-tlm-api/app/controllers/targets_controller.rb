# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'openc3/models/target_model'

class TargetsController < ModelController
  def initialize
    @model_class = OpenC3::TargetModel
  end

  # All targets with indication of modified targets
  def all_modified
    return unless authorization('system')
    render :json => @model_class.all_modified(scope: params[:scope])
  end

  def download
    return unless authorization('system')
    begin
      file = @model_class.download(params[:id], scope: params[:scope])
      if file
        results = { 'filename' => file.filename, 'contents' => Base64.encode64(file.contents) }
        render json: results
      else
        head :not_found
      end
    rescue Exception => e
      render(json: { status: 'error', message: e.message }, status: 500) and
        return
    end
  end
end
