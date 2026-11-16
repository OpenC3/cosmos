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

# Enterprise feature. Real implementation lives in the openc3-enterprise gem
# at lib/openc3-enterprise/controllers/dashboard_version_controller.rb. Core
# builds resolve the routes to this empty stub so Rails autoload succeeds.
begin
  require 'openc3-enterprise/controllers/dashboard_version_controller'
rescue LoadError
  class DashboardVersionController
  end
end
