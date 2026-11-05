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
# at lib/openc3-enterprise/controllers/script_version_controller.rb. Core
# build resolves the routes to this empty stub so Rails autoload succeeds;
# requests then 404 on the missing action rather than ActionDispatch::MissingController.
begin
  require 'openc3-enterprise/controllers/script_version_controller'
rescue LoadError
  class ScriptVersionController
  end
end
