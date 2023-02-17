OpenC3::StreamingWebSocketApi.new do |api|
  api.add(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'])
  5.times do
    puts api.read
  end
  api.remove(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED'])
  5.times do
    puts api.read
  end
end

# Warning this saves all data to RAM. Do not use for large queries
data = OpenC3::StreamingWebSocketApi.read_all(items: ['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED', 'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'], end_time: Time.now + 10)
puts data.length
puts data[0].inspect
