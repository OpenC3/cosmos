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

# For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
Rails.application.routes.draw do
  scope "script-api" do
    get "/ping" => "scripts#ping"
    get  "/scripts" => "scripts#index"
    delete "/scripts/temp_files" => "scripts#delete_temp"
    # Must come before /scripts/*name so /lifecycle matches first
    get  "/scripts/*name/lifecycle" => "scripts#lifecycle", format: false, defaults: { format: 'html' }
    # Enterprise-only Version History export/import. Per-plugin (one git repo
    # per installed plugin), so both are keyed by plugin base name, not file
    # name. Literal "/scripts/plugin/..." prefix declared before the *name
    # catchalls so they don't match scripts#create / scripts#body.
    # ScriptVersionController lives in the openc3-enterprise gem; in Core builds
    # requests here 500 with uninitialized constant (matches the notebooks/chat
    # pattern).
    post "/scripts/plugin/:plugin/history-import" => "script_version#import_history"
    get  "/scripts/plugin/:plugin/history-export" => "script_version#export_history"
    # Specific GET routes must precede the catchall body route below — Rails
    # matches in declaration order and *name is greedy, so /foo.rb/versions
    # would otherwise match #body with name="foo.rb/versions". Enterprise-only.
    get  "/scripts/*name/versions" => "script_version#versions", format: false, defaults: { format: 'html' }
    get  "/scripts/*name/version" => "script_version#version_body", format: false, defaults: { format: 'html' }
    get  "/scripts/*name" => "scripts#body", format: false, defaults: { format: 'html' }
    post "/scripts/*name/run(/:disconnect)" => "scripts#run", format: false, defaults: { format: 'html' }
    post "/scripts/*name/delete" => "scripts#destroy", format: false, defaults: { format: 'html' }
    post "/scripts/*name/lock" => "scripts#lock"
    post "/scripts/*name/unlock" => "scripts#unlock"
    post "/scripts/*name/syntax" => "scripts#syntax"
    post "/scripts/*name/mnemonics" => "scripts#mnemonics"
    post "/scripts/*name/instrumented" => "scripts#instrumented"
    post "/scripts/*name/lifecycle" => "scripts#set_lifecycle", format: false, defaults: { format: 'html' }
    # Enterprise-only restore.
    post "/scripts/*name/restore" => "script_version#restore", format: false, defaults: { format: 'html' }
    # Must be last so /run, /delete, etc will match first
    post "/scripts/*name" => "scripts#create", format: false, defaults: { format: 'html' }

    delete "/breakpoints/delete/all" => "scripts#delete_all_breakpoints"

    get  "/running-script" => "running_script#index"
    get  "/running-script/:id" => "running_script#show"
    post "/running-script/:id/stop" => "running_script#stop"
    post "/running-script/:id/pause" => "running_script#pause"
    post "/running-script/:id/retry" => "running_script#retry"
    post "/running-script/:id/go" => "running_script#go"
    post "/running-script/:id/step" => "running_script#step"
    post "/running-script/:id/prompt" => "running_script#prompt"
    post "/running-script/:id/delete" => "running_script#delete"
    post "/running-script/:id/:method" => "running_script#method"
    get  "/completed-scripts" => "completed_script#index"
  end
end
