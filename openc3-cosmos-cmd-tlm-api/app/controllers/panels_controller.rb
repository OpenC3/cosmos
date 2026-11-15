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

require 'openc3/models/panel_model'

# Lists the panel types plugins have installed (GET /panels returns
# their names); the Dashboards tool loads each from
# /tools/panels/<NAME>/<NAME>.js
class PanelsController < ModelController
  def initialize
    @model_class = OpenC3::PanelModel
  end
end
