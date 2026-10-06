# encoding: ascii-8bit

# Create the overall gemspec
Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-arduino-sensor-kit'
  s.summary = 'Arduino Sensor Kit'
  s.description = <<-EOF
    This plugin enables monitoring and interactivity with the Arduino Sensor Kit
  EOF
  s.license = 'MIT'
  s.authors = ['Clay Kramp']
  s.email = ['clay@openc3.com']
  s.homepage = 'https://github.com/OpenC3/openc3-cosmos-arduino-sensor-kit'
  s.version = "1.0.0"
  s.platform = Gem::Platform::RUBY

  s.metadata = {
    "source_code_uri" => "https://github.com/OpenC3/openc3-cosmos-arduino-sensor-kit",
    "openc3_minimum_cosmos_version" => "5.0.0",
    "openc3_store_access_type" => "public",
    "openc3_store_keywords" => "Arduino, BMP280, DHT20, Accelerometer"
  }

  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile README.md LICENSE.txt plugin.txt)
end
