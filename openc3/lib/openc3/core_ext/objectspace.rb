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

# OpenC3 specific additions to the ObjectSpace class
module ObjectSpace
  def self.find(klass)
    ObjectSpace.each_object(klass) do |object|
      return object
    end
    nil
  end

  def self.find_all(klass)
    objects = []
    ObjectSpace.each_object(klass) do |object|
      objects << object
    end
    objects
  end
end # class ObjectSpace
