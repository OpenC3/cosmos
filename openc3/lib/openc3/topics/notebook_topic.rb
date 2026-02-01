# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/topics/topic'

module OpenC3
  class NotebookTopic < Topic
    PRIMARY_KEY = "__openc3_notebook"

    # Write a notebook event to the topic
    #
    # ```json
    #  "type" => "notebook",
    #  "kind" => "saved",  # saved, deleted, started, completed
    #  "data" => {
    #    "target" => "INST",
    #    "notebook" => "EXAMPLE",
    #    "id" => "12345",
    #    "updated_at" => 1621875570000000000,
    #    "username" => "admin"
    #  }
    # ```
    def self.write_entry(entry, scope:)
      Topic.write_topic("#{scope}#{PRIMARY_KEY}", entry, '*', 1000)
    end
  end
end
