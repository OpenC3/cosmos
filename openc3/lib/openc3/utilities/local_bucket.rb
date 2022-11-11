# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.

require 'openc3/utilities/aws_bucket'

module OpenC3
  # This class exists simply to enable the following code in bucket.rb
  #   bucket_class = ENV['OPENC3_CLOUD'].capitalize + 'Bucket'
  # So when the OPENC3_CLOUD var is set to 'local' this file is used
  # The local code uses Minio which is identical to the Aws APIs
  class LocalBucket < AwsBucket
  end
end
