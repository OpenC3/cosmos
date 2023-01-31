require 'tmpdir'
require 'json'
require 'fileutils'

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
  result = system("docker save #{image_name} > image.tar")
  if result
    # Untar to reveal manifest.json and layer tar files
    tar_result = system("tar xvf image.tar")
    if tar_result
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
        Dir.chdir("container#{index}")

        # Untar layers in order
        manifest['Layers'].each do |layer_tar|
          tar_result = system("tar xvf ../#{layer_tar}")
          unless tar_result
            puts "Failed to tar xvf ../#{layer_tar}"
            exit 1
          end
        end

        # Do the ClamAV scan!
        clam_results = `docker run -it --rm -v clamav:/var/lib/clamav -v "#{temp_dir}/container#{index}:/scanme:ro" clamav/clamav clamscan -ri /scanme`
        puts clam_results

        Dir.chdir(temp_dir)
      end
    else
      puts "Failed to tar xvf image.tar"
      exit 1
    end
  else
    puts "Failed to docker save #{image_name}"
    exit 1
  end
ensure
  FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
end
