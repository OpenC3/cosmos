require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/timeline_model'

module OpenC3
  class ActivityUuid < Migration
    def self.run
      ScopeModel.names.each do |scope|
        TimelineModel.names.each do |key|
          name = key.split('__').last
          json = Store.zrange("#{scope}#{ActivityModel::PRIMARY_KEY}__#{name}", 0, -1)
          parsed = json.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
          parsed.each_with_index do |activity, index|
            if activity['uuid'].nil?
              activity['uuid'] = SecureRandom.uuid
              Store.zrem("#{scope}#{ActivityModel::PRIMARY_KEY}__#{name}", json[index])
              Store.zadd("#{scope}#{ActivityModel::PRIMARY_KEY}__#{name}", activity['start'], JSON.generate(activity))
            end
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::ActivityUuid.run
end
