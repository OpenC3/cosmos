require 'tmpdir'
require 'json'
require 'fileutils'
require 'open3'

image_name = ARGV[0]
unless image_name
  puts "Usage: ruby clamav_scan_image.rb IMAGE_NAME"
  exit 1
end

pull = ARGV[1]

append_filename = ARGV[2]
if append_filename
  output_file = File.open(append_filename, 'a')
else
  output_file = STDOUT
end

output_file.puts "Performing ClamAV scan of #{image_name}"
output_file.puts

# Create a temp directory to hold the layer tar files
temp_dir = Dir.mktmpdir
begin
  Dir.chdir(temp_dir)

  # Get the overall tar file
  if pull
    docker_output, result = Open3.capture2e("docker pull #{image_name}")
    if not result.success?
      output_file.puts docker_output
      output_file.puts "Failed to docker pull #{image_name}"
      exit 1
    end
  end
  docker_output, result = Open3.capture2e("docker save #{image_name} > image.tar")
  if result.success?
    # Untar to reveal manifest.json and layer tar files
    tar_output, tar_result = Open3.capture2e("tar xvf image.tar")
    if tar_result.success?
      # Read the manifest so we can use the layers in the right order
      json_data = File.read("manifest.json")
      json_array = JSON.parse(json_data)
      json_array.each_with_index do |manifest, index|
        output_file.puts "Config: #{manifest['Config']}"
        output_file.puts "RepoTags: #{manifest['RepoTags']}"
        output_file.puts "Layers:"
        manifest['Layers'].each do |layer_tar|
          output_file.puts layer_tar
        end

        # Create a subdirectory to build the full container
        FileUtils.mkdir_p("container#{index}")
        FileUtils.mkdir_p("container#{index}/usr/bin")
        FileUtils.mkdir_p("container#{index}/usr/sbin")
        FileUtils.mkdir_p("container#{index}/usr/lib")
        FileUtils.mkdir_p("container#{index}/usr/lib64/pm-utils/module.d")
        FileUtils.mkdir_p("container#{index}/usr/lib64/pm-utils/power.d")
        FileUtils.mkdir_p("container#{index}/usr/lib64/pm-utils/sleep.d")
        Dir.chdir("container#{index}")

        # Untar layers in order
        manifest['Layers'].each do |layer_tar|
          # Make sure tar will have permissions
          chmod_output, chmod_result = Open3.capture2e("chmod -R 777 .")
          unless chmod_result.success?
            output_file.puts chmod_output
            output_file.puts "Failed to chmod -R 777 ."
            exit 1
          end

          tar_output, tar_result = Open3.capture2e("tar xvf ../#{layer_tar}")
          unless tar_result.success?
            output_file.puts tar_output
            output_file.puts "Failed to tar xvf ../#{layer_tar}"
            exit 1
          end
        end

        # Make sure ClamAV will have permissions
        chmod_output, chmod_result = Open3.capture2e("chmod -R 777 .")
        unless chmod_result.success?
          output_file.puts chmod_output
          output_file.puts "Failed to chmod -R 777 ."
          exit 1
        end

        # Do the ClamAV scan!
        if output_file == STDOUT
          clam_output, _ = Open3.capture2e("docker run --rm -v clamav:/var/lib/clamav -v \"#{temp_dir}/container#{index}:/scanme:ro\" clamav/clamav clamscan -ri /scanme")
        else
          # List all files
          clam_output, _ = Open3.capture2e("docker run --rm -v clamav:/var/lib/clamav -v \"#{temp_dir}/container#{index}:/scanme:ro\" clamav/clamav clamscan -r /scanme")
        end
        output_file.puts clam_output
        output_file.puts
        clam_output.each_line do |line|
          if line =~ /Infected files/
            split_line = line.split(": ")
            count = split_line[-1].strip.to_i
            if count != 0
              exit 1
            end
            break
          end
        end

        Dir.chdir(temp_dir)
      end
    else
      output_file.puts tar_output
      output_file.puts "Failed to tar xvf image.tar"
      exit 1
    end
  else
    output_file.puts docker_output
    output_file.puts "Failed to docker save #{image_name}"
    exit 1
  end
ensure
  FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
  if append_filename
    output_file.close
  end
end

exit 0