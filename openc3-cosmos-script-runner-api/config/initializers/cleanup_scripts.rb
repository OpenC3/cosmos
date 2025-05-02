require 'openc3/models/scope_model'
require 'openc3/models/script_status_model'

unless ENV['CI']
  # ScriptRunner has restarted so any running scripts are assumed killed by the restart
  shard = ENV['OPENC3_SHARD'].to_i
  scopes = OpenC3::ScopeModel.all
  scopes.each do |scope_name, scope|
    OpenC3::ScriptStatusModel.all(scope: scope_name, type: 'running').each do |script_status|
      if script_status['shard'].to_i == shard
        model = OpenC3::ScriptStatusModel.from_json(script_status, scope: scope_name)
        model.state = 'killed'
        model.end_time = Time.now.utc.iso8601
        model.update
      end
    end
  end
end