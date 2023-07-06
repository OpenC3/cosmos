require 'openc3/utilities/migration'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'
require 'openc3/models/reaction_model'

module OpenC3
  class Autonomic < Migration
    def self.run
      ScopeModel.names.each do |scope|
        puts "Processing scope #{scope}"

        # Update all old TriggerModels just so they work when we delete the ReactionModel
        # Because the ReactionModel verifies the triggers
        delete_all_triggers = false
        groups = TriggerGroupModel.all(scope: scope)
        groups.each do |key, group_hash|
          puts "Processing group #{group_hash['name']}"
          if group_hash.has_key?('color')
            group_hash.delete('color')
            group = TriggerGroupModel.from_json(group_hash, name: group_hash['name'], scope: scope)
            group.update()
          end
          TriggerModel.all(group: group_hash['name'], scope: scope).each do |key, model_hash|
            if model_hash.has_key?('description') or model_hash.has_key?('active')
              puts "Updating TriggerModel: #{model_hash['name']}"
              model_hash.delete('description')
              model_hash.delete('active')
              model_hash['left'] = {'type' => 'item', 'target' => 'TGT', 'packet' => 'PKT', 'item' => 'ITEM', 'valueType' => 'CONVERTED'}
              model_hash['operator'] = 'CHANGES'
              model_hash['right'] = nil
              TriggerModel.from_json(model_hash, name: model_hash['name'], scope: scope).update()
              delete_all_triggers = true
            end
          end
        end

        # Remove all old ReactionModels
        ReactionModel.all(scope: scope).each do |key, model_hash|
          if model_hash.has_key?('description') or model_hash.has_key?('review') or model_hash.has_key?('active')
            # Can't delete directly because delete calls get which calls from_json which calls new
            # and at that point we get missing keyword: :triggerLevel (ArgumentError)
            # So update to add triggerLevel
            model_hash['triggerLevel'] = 'EDGE'
            model_hash.delete('description')
            model_hash.delete('review')
            model_hash.delete('active')
            ReactionModel.from_json(model_hash, name: model_hash['name'], scope: scope).update()
            puts "Deleting ReactionModel: #{model_hash['name']}"
            ReactionModel.delete(name: model_hash['name'], scope: scope)
          end
        end

        # Remove all old TriggerModels and TriggerGroupModels
        if delete_all_triggers
          groups = TriggerGroupModel.all(scope: scope)
          groups.each do |key, group_hash|
            TriggerModel.all(group: group_hash['name'], scope: scope).each do |key, trigger_hash|
              puts "Deleting TriggerModel: #{trigger_hash['name']}"
              TriggerModel.delete(name: trigger_hash['name'], group: group_hash['name'], scope: scope)
            end
            group = TriggerGroupModel.from_json(group_hash, name: group_hash['name'], scope: scope)
            group.undeploy()
            puts "Deleting TriggerGroupModel: #{group_hash['name']}"
            TriggerGroupModel.delete(name: group_hash['name'], scope: scope)
          end
        end

        # Create DEFAULT trigger group model
        model = TriggerGroupModel.get(name: 'DEFAULT', scope: scope)
        unless model
          puts "Creating TriggerGroupModel: DEFAULT"
          model = TriggerGroupModel.new(name: 'DEFAULT', scope: scope)
          model.create()
          model.deploy()
        end
      end
    rescue => error
      puts error.message
      puts error.backtrace
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::Autonomic.run
end
