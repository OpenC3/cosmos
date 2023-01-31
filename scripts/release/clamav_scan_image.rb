require 'tmpdir'
require 'json'
require 'fileutils'
require 'open3'

image_name = ARGV[0]
unless image_name
  puts "Usage: ruby clamav_scan_image.rb IMAGE_NAME"
  exit 1
end

# Create a temp directory to hold the layer tar files
temp_dir = Dir.mktmpdir
begin
  Dir.chdir(temp_dir)

  # Get the overall tar file
  docker_output, result = Open3.capture2e("docker save #{image_name} > image.tar")
  if result.success?
    # Untar to reveal manifest.json and layer tar files
    tar_output, tar_result = Open3.capture2e("tar xvf image.tar")
    if tar_result.success?
      # Read the manifest so we can use the layers in the right order
      json_data = File.read("manifest.json")
      json_array = JSON.parse(json_data)
      json_array.each_with_index do |manifest, index|
        puts "Config: #{manifest['Config']}"
        puts "RepoTags: #{manifest['RepoTags']}"
        puts "Layers:"
        manifest['Layers'].each do |layer_tar|
          puts layer_tar
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
          tar_output, tar_result = Open3.capture2e("tar xvf ../#{layer_tar}")
          unless tar_result.success?
            puts tar_output
            puts "Failed to tar xvf ../#{layer_tar}"
            exit 1
          end
        end

        # Make sure ClamAV will have permissions
        chmod_output, chmod_result = Open3.capture2e("chmod -R 777 .")
        unless chmod_result.success?
          puts chmod_output
          puts "Failed to chmod -R 777 ."
          exit 1
        end

        # Do the ClamAV scan!
        clam_output, _ = Open3.capture2e("docker run --rm -v clamav:/var/lib/clamav -v \"#{temp_dir}/container#{index}:/scanme:ro\" clamav/clamav clamscan -ri /scanme")
        puts clam_output
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
      puts tar_output
      puts "Failed to tar xvf image.tar"
      exit 1
    end
  else
    puts docker_output
    puts "Failed to docker save #{image_name}"
    exit 1
  end
ensure
  FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
end

exit 0