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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

Rails.application.routes.draw do
  AUTONOMIC_REACTION = '/autonomic/reaction'
  AUTONOMIC_GROUP = '/autonomic/group'
  AUTONOMIC_GROUP_TRIGGER = '/autonomic/:group/trigger'
  INTERFACES_ID = '/interfaces/:id'
  METADATA_ID = '/metadata/:id'
  MICROSERVICES_ID = '/microservices/:id'
  NOTES_ID = '/notes/:id'
  PLUGINS_ID =  '/plugins/:id'
  ROLES_ID = '/roles/:id'
  ROUTERS_ID = '/routers/:id'
  SCOPES_ID = '/scopes/:id'
  TABLES_NAME = '/tables/*name'
  TARGETS_ID = '/targets/:id'
  TIMELINE_ACTIVITY_ID = '/timeline/:name/activity/:id'
  TIMELINE_NAME = '/timeline/:name'
  TOOLS_ID = '/tools/:id'
  WIDGETS_ID = '/widgets/:id'

  scope "openc3-api" do
    resources :routers, only: [:index, :create]
    get ROUTERS_ID, to: 'routers#show', id: /[^\/]+/
    match ROUTERS_ID, to: 'routers#update', id: /[^\/]+/, via: [:patch, :put]
    delete ROUTERS_ID, to: 'routers#destroy', id: /[^\/]+/

    resources :interfaces, only: [:index, :create]
    get INTERFACES_ID, to: 'interfaces#show', id: /[^\/]+/
    match INTERFACES_ID, to: 'interfaces#update', id: /[^\/]+/, via: [:patch, :put]
    delete INTERFACES_ID, to: 'interfaces#destroy', id: /[^\/]+/

    resources :targets, only: [:index, :create]
    get TARGETS_ID, to: 'targets#show', id: /[^\/]+/
    get TARGETS_ID + '/modified_files', to: 'targets#modified_files', id: /[^\/]+/
    get '/targets_modified', to: 'targets#all_modified'
    match TARGETS_ID, to: 'targets#update', id: /[^\/]+/, via: [:patch, :put]
    delete TARGETS_ID, to: 'targets#destroy', id: /[^\/]+/
    post TARGETS_ID + '/download', to: 'targets#download', id: /[^\/]+/
    post TARGETS_ID + '/delete_modified', to: 'targets#delete_modified', id: /[^\/]+/

    resources :packages, only: [:index, :create]
    delete '/packages/:id', to: 'packages#destroy', id: /[^\/]+/
    post '/packages/:id/download', to: 'packages#download', id: /[^\/]+/

    resources :microservices, only: [:index, :create]
    get MICROSERVICES_ID , to: 'microservices#show', id: /[^\/]+/
    match MICROSERVICES_ID , to: 'microservices#update', id: /[^\/]+/, via: [:patch, :put]
    delete MICROSERVICES_ID , to: 'microservices#destroy', id: /[^\/]+/

    resources :process_status, only: [:index]
    get '/process_status/:id', to: 'process_status#show', id: /[^\/]+/

    get '/microservice_status/:id', to: 'microservice_status#show', id: /[^\/]+/

    post '/tools/position/:id', to: 'tools#position', id: /[^\/]+/
    resources :tools, only: [:index, :create]
    get TOOLS_ID, to: 'tools#show', id: /[^\/]+/
    match TOOLS_ID, to: 'tools#update', id: /[^\/]+/, via: [:patch, :put]
    delete TOOLS_ID, to: 'tools#destroy', id: /[^\/]+/

    resources :scopes, only: [:index, :create]
    get SCOPES_ID, to: 'scopes#show', id: /[^\/]+/
    match SCOPES_ID, to: 'scopes#update', id: /[^\/]+/, via: [:patch, :put]
    delete SCOPES_ID, to: 'scopes#destroy', id: /[^\/]+/

    resources :widgets, only: [:index, :create]
    get WIDGETS_ID, to: 'widgets#show', id: /[^\/]+/
    match WIDGETS_ID, to: 'widgets#update', id: /[^\/]+/, via: [:patch, :put]
    delete WIDGETS_ID, to: 'widgets#destroy', id: /[^\/]+/

    resources :permissions, only: [:index]

    post '/plugins/install/:id', to: 'plugins#install', id: /[^\/]+/
    resources :plugins, only: [:index, :create]
    get PLUGINS_ID, to: 'plugins#show', id: /[^\/]+/
    match PLUGINS_ID, to: 'plugins#update', id: /[^\/]+/, via: [:patch, :put]
    delete PLUGINS_ID, to: 'plugins#destroy', id: /[^\/]+/

    resources :environment, only: [:index, :create]
    delete '/environment/:name', to: 'environment#destroy', name: /[^\/]+/

    resources :timeline, only: [:index, :create]
    get TIMELINE_NAME, to: 'timeline#show', name: /[^\/]+/
    post TIMELINE_NAME + '/color', to: 'timeline#color', name: /[^\/]+/
    delete TIMELINE_NAME, to: 'timeline#destroy', name: /[^\/]+/

    post '/timeline/activities/create', to: 'activity#multi_create'
    post '/timeline/activities/delete', to: 'activity#multi_destroy'

    get TIMELINE_NAME + '/count', to: 'activity#count', name: /[^\/]+/
    get TIMELINE_NAME + '/activities', to: 'activity#index', name: /[^\/]+/
    post TIMELINE_NAME + '/activities', to: 'activity#create', name: /[^\/]+/
    get TIMELINE_ACTIVITY_ID, to: 'activity#show', name: /[^\/]+/, id: /[^\/]+/
    post TIMELINE_ACTIVITY_ID, to: 'activity#event', name: /[^\/]+/, id: /[^\/]+/
    match TIMELINE_ACTIVITY_ID, to: 'activity#update', name: /[^\/]+/, id: /[^\/]+/, via: [:patch, :put]
    delete TIMELINE_ACTIVITY_ID, to: 'activity#destroy', name: /[^\/]+/, id: /[^\/]+/

    get AUTONOMIC_GROUP, to: 'trigger_group#index'
    post AUTONOMIC_GROUP, to: 'trigger_group#create'
    get AUTONOMIC_GROUP + '/:group', to: 'trigger_group#show', group: /[^\/]+/
    delete AUTONOMIC_GROUP + ':group', to: 'trigger_group#destroy', group: /[^\/]+/

    get AUTONOMIC_GROUP_TRIGGER, to: 'trigger#index', group: /[^\/]+/
    post AUTONOMIC_GROUP_TRIGGER, to: 'trigger#create', group: /[^\/]+/
    get AUTONOMIC_GROUP_TRIGGER + '/:name', to: 'trigger#show', group: /[^\/]+/, name: /[^\/]+/
    post AUTONOMIC_GROUP_TRIGGER + '/:name/enable', to: 'trigger#enable', group: /[^\/]+/, name: /[^\/]+/
    post AUTONOMIC_GROUP_TRIGGER + '/:name/disable', to: 'trigger#disable', group: /[^\/]+/, name: /[^\/]+/
    match AUTONOMIC_GROUP_TRIGGER + '/:name', to: 'trigger#update', group: /[^\/]+/, name: /[^\/]+/, via: [:patch, :put]
    delete AUTONOMIC_GROUP_TRIGGER + '/:name', to: 'trigger#destroy', group: /[^\/]+/, name: /[^\/]+/

    get AUTONOMIC_REACTION, to: 'reaction#index'
    post AUTONOMIC_REACTION, to: 'reaction#create'
    get AUTONOMIC_REACTION + '/:name/', to: 'reaction#show', name: /[^\/]+/
    # match '/autonomic/reaction/:name, to: 'reaction#update', name: /[^\/]+/, via: [:patch, :put]
    post AUTONOMIC_REACTION + '/:name/enable', to: 'reaction#enable', name: /[^\/]+/
    post AUTONOMIC_REACTION + '/:name/disable', to: 'reaction#disable', name: /[^\/]+/
    post AUTONOMIC_REACTION + '/:name/execute', to: 'reaction#execute', name: /[^\/]+/
    match AUTONOMIC_REACTION + '/:name', to: 'reaction#update', name: /[^\/]+/, via: [:patch, :put]
    delete AUTONOMIC_REACTION + '/:name', to: 'reaction#destroy', name: /[^\/]+/

    get '/metadata', to: 'metadata#index'
    post '/metadata', to: 'metadata#create'
    get '/metadata/latest', to: 'metadata#latest', name: /[^\/]+/
    # get '/metadata/_search', to: 'metadata#search'
    get METADATA_ID, to: 'metadata#show', id: /[^\/]+/
    match METADATA_ID, to: 'metadata#update', id: /[^\/]+/, via: [:patch, :put]
    delete METADATA_ID, to: 'metadata#destroy', id: /[^\/]+/

    get '/notes', to: 'notes#index'
    post '/notes', to: 'notes#create'
    # get '/note/_search', to: 'note#search'
    get NOTES_ID, to: 'notes#show', id: /[^\/]+/
    match NOTES_ID, to: 'notes#update', id: /[^\/]+/, via: [:patch, :put]
    delete NOTES_ID, to: 'notes#destroy', id: /[^\/]+/

    get '/autocomplete/reserved-item-names', to: 'script_autocomplete#reserved_item_names'
    get '/autocomplete/keywords/:type', to: 'script_autocomplete#keywords', type: /[^\/]+/
    get '/autocomplete/data/:type', to: 'script_autocomplete#ace_autocomplete_data', type: /[^\/]+/

    # format: false to ensure the full path is used and not interpreted as a format (.xxx)
    scope format: false do
      get '/storage/buckets', to: 'storage#buckets'
      get '/storage/volumes', to: 'storage#volumes'
      get '/storage/files/:root/(*path)', to: 'storage#files'
      get '/storage/exists/:object_id', to: 'storage#exists', object_id: /.*/
      get '/storage/download_file/:object_id', to: 'storage#download_file', object_id: /.*/
      get '/storage/download/:object_id', to: 'storage#get_download_presigned_request', object_id: /.*/
      get '/storage/upload/:object_id', to: 'storage#get_upload_presigned_request', object_id: /.*/
      delete '/storage/delete/:object_id', to: 'storage#delete', object_id: /.*/
    end

    get  '/tables', to: 'tables#index'
    # format: false to ensure the file extension (.bin, .txt) remains and is passed to 'name'
    get  TABLES_NAME, to: 'tables#body', format: false, defaults: { format: 'html' }
    post TABLES_NAME + '/lock', to: 'tables#lock'
    post TABLES_NAME + '/unlock', to: 'tables#unlock'
    post '/tables/binary', to: 'tables#binary'
    post '/tables/definition', to: 'tables#definition'
    post '/tables/report', to: 'tables#report'
    post '/tables/load', to: 'tables#load'
    post '/tables/generate', to: 'tables#generate'
    # Allow new_name to contain anything (including a dot '.')
    put TABLES_NAME + '/save-as/*new_name', to: 'tables#save_as', new_name: /.*/
    # Must be last post /tables/*name so others will match first
    post TABLES_NAME, to: 'tables#save'
    delete TABLES_NAME, to: 'tables#destroy', format: false

    get "/screens", to: "screens#index"
    get "/screen/:target/:screen", to: "screens#show"
    post "/screen", to: "screens#create"
    delete '/screen/:target/:screen', to: 'screens#destroy'

    get "/secrets", to: "secrets#index"
    post "/secrets/:key", to: "secrets#create", key: /[^\/]+/
    delete '/secrets/:key', to: 'secrets#destroy', key: /[^\/]+/

    # This route handles all the JSON DRB requests
    # It gets routed to the api_controller.rb api method which
    # ultimately calls OpenC3::Cts.instance.json_drb.process_request
    # to do the remote procedure call
    post "/api" => "api#api"
    get "/ping" => "api#ping"

    get "/auth/token-exists" => "auth#token_exists"
    post "/auth/verify" => "auth#verify"
    post "/auth/set" => "auth#set"

    get "/internal/health" => "internal_health#health"
    get "/internal/metrics" => "internal_metrics#index"
    get "/internal/status" => "internal_status#status"

    get "/time" => "time#get_current"
    get "map.json" => "tools#importmap"
    get "auth.js" => "tools#auth"
    get "/traefik" => "microservices#traefik"

    post "/redis/exec" => "redis#execute_raw"

    # The remaining routes are Enterprise only
    get "/users/active" => "users#active"
    match "/users/logout/:user", to: "users#logout", id: /[^\/]+/, via: [:patch, :put]

    get "/info" => "info#info"

    resources :roles, only: [:index, :create]
    get ROLES_ID, to: 'roles#show', id: /[^\/]+/
    match ROLES_ID, to: 'roles#update', id: /[^\/]+/, via: [:patch, :put]
    delete ROLES_ID, to: 'roles#destroy', id: /[^\/]+/

    get '/cmdauth', to: 'cmd_authority#index'
    post '/cmdauth/take', to: 'cmd_authority#take'
    post '/cmdauth/release', to: 'cmd_authority#release'
    post '/cmdauth/take-all', to: 'cmd_authority#take_all'
    post '/cmdauth/release-all', to: 'cmd_authority#release_all'
  end
end
