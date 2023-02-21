# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  class CliGenerator
    GENERATORS = %w(plugin conversion microservice)

    # Called by openc3cli with ARGV[1..-1]
    def self.generate(args)
      unless GENERATORS.include?(args[0])
        abort("Unknown generator '#{args[0]}'. Valid generators: #{GENERATORS.join(', ')}")
      end
      send("generate_#{args[0]}", args)
    end

    def self.generate_plugin(args)
      if args.length != 2
        abort("Usage: cli generate plugin <NAME>")
      end
      if args[1] =~ /\s/
        abort("Plugin name can not have spaces!")
      end

      plugin = args[1].downcase.gsub(/_+|-+/, '-')
      plugin_name = "openc3-cosmos-#{plugin}"
      if File.exist?(plugin_name)
        abort("Plugin #{plugin_name} already exists!")
      end
      FileUtils.mkdir(plugin_name)
      Dir.chdir(plugin_name) # Change to the plugin path to make copying easier

      # Grab the plugin template
      template_dir = "#{File.dirname(__FILE__)}/../../../templates/plugin"
      target_name = plugin.upcase.gsub('-', '_')
      target_lib_filename = "#{target_name.downcase}.rb"
      target_class = target_lib_filename.filename_to_class_name
      target_object = target_name.downcase
      b = binding

      Dir.glob("#{template_dir}/**/*").each do |file|
        base_name = file.sub("#{template_dir}/", '')
        # Rename the template TARGET to our actual target named after the plugin
        base_name.sub!("targets/TARGET", "targets/#{target_name}")
        if File.directory?(file)
          FileUtils.mkdir(base_name)
          next
        end
        base_name.sub!("target.rb", target_lib_filename)
        base_name.sub!("plugin.gemspec", "#{plugin_name}.gemspec")
        output = ERB.new(File.read(file), trim_mode: "-").result(b)
        File.open(base_name, 'w') do |file|
          file.write output
        end
      end

      puts "Plugin #{plugin_name} successfully generated!\n"
      return target_name # This makes the migrate method easier
    end

    def self.generate_microservice(args)
      if args.length != 2
        abort("Usage: cli generate microservice <NAME>")
      end
      if args[1] =~ /\s/
        abort("Microservice name can not have spaces!")
      end
      if Dir.glob("*.gemspec").empty?
        abort("No gemspec file detected. Microservice generator should be run within an existing plugin.")
      end
      microservice_name = args[1].upcase.gsub(/_+|-+/, '_')
      microservice_path = "microservices/#{microservice_name}"

      if File.exist?(microservice_path)
        abort("Microservice #{microservice_path} already exists!")
      end

      # Grab the microservice template
      template_dir = "#{File.dirname(__FILE__)}/../../../templates/microservice"
      microservice_filename = "#{microservice_name.downcase}.rb"
      microservice_class = microservice_filename.filename_to_class_name
      b = binding

      Dir.glob("#{template_dir}/**/*").each do |file|
        base_name = file.sub("#{template_dir}/", '')
        # Rename the template MICROSERVICE to our actual microservice name
        base_name.sub!("microservices/TEMPLATE", "microservices/#{microservice_name}")
        if File.directory?(file)
          FileUtils.mkdir(base_name)
          next
        end
        base_name.sub!("template.rb", microservice_filename)
        output = ERB.new(File.read(file), trim_mode: "-").result(b)
        File.open(base_name, 'w') do |file|
          file.write output
        end
      end
      File.open("plugin.txt", 'a') do |file|
        file.puts <<~DOC

          MICROSERVICE #{microservice_name} #{microservice_name.downcase.gsub('_','-')}-microservice
            CMD ruby #{microservice_name.downcase}.rb
        DOC
      end

      puts "Microservice #{microservice_name} successfully generated!\n"
      return microservice_name
    end

    def self.generate_conversion(args)
      if args.length != 3
        abort("Usage: cli generate conversion <TARGET> <CONVERSION>")
      end
      if Dir.glob("*.gemspec").empty?
        abort("No gemspec file detected. Conversion generator should be run within an existing plugin.")
      end
      target_name = args[1].upcase
      unless File.exist?("targets/#{target_name}")
        abort("Target '#{target_name}' does not exist! Conversions must be created for existing targets.")
      end
      if args[2] =~ /\s/
        abort("Conversion name can not have spaces!")
      end
      conversion_name = args[2].upcase.gsub(/_+|-+/, '_')
      conversion_path = "targets/#{target_name}/lib/"
      conversion_basename = "#{conversion_name.downcase}.rb"
      conversion_class = conversion_basename.filename_to_class_name
      conversion_filename = "targets/#{target_name}/lib/#{conversion_basename}"
      if File.exist?(conversion_filename)
        abort("Conversion #{conversion_filename} already exists!")
      end
      template_dir = "#{File.dirname(__FILE__)}/../../../templates/conversion"
      b = binding

      Dir.glob("#{template_dir}/**/*").each do |file|
        base_name = file.sub("#{template_dir}/", '')
        # Rename the template conversion to our actual conversion name
        base_name.sub!("template.rb", conversion_filename)
        output = ERB.new(File.read(file), trim_mode: "-").result(b)
        File.open(base_name, 'w') do |file|
          file.write output
        end
      end

      puts "Conversion #{conversion_filename} successfully generated!\n"
      puts "To use the conversion add the following to a telemetry item:"
      puts "  READ_CONVERSION #{conversion_basename}"
      return conversion_name
    end
  end
end
