require 'openc3/utilities/migration'
require 'openc3/models/scope_model'

module OpenC3
  class Autonomic < Migration
    def self.run
      ScopeModel.names.each do |scope|
        # Get all existing TriggerGroupModels and remove color
        groups = TriggerGroupModel.all(scope: scope)
        groups.each do |key, model_hash|
          if model_hash.has_key?('color')
            model_hash.delete('color')
            TriggerGroupModel.from_json(model_hash, scope: scope).update
          end
        end

        # Get all existing TriggerModels and change name to TRIG[X]
        # Remove description
        triggers = TriggerModel.all(scope: scope)
        i = 1
        triggers.each do |key, model_hash|
          if model_hash.has_key?('description')
            model_hash.delete('description')
            model_hash['name'] = "TRIG#{i}"
            TriggerModel.from_json(model_hash, scope: scope).update
            i += 1
          end
        end

        # Get all existing ReactionModels and change name to REACT[X]
        # Remove review and description and set triggerLevel
        reactions = ReactionModel.all(scope: scope)
        i = 1
        reactions.each do |key, model_hash|
          if model_hash.has_key?('description')
            model_hash.delete('review')
            model_hash.delete('description')
            model_hash['triggerLevel'] = 'EDGE'
            model_hash['name'] = "REACT#{i}"
            ReactionModel.from_json(model_hash, scope: scope).update
            i += 1
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::Autonomic.run
end
