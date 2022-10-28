require_relative 'streaming_object_collection'

class StreamingObjectCollectionFileReader
  FILE_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S%N"
  DIRECTORY_TIMESTAMP_FORMAT = "%Y%m%d"
  NANOSECONDS_PER_DAY = Time::SEC_PER_DAY * Time::NSEC_PER_SECOND

  def initialize(scope:)
    @bucket = OpenC3::Bucket.getClient()
    @scope = scope
  end

  def each(collection)
    targets_and_types, start_time_nsec, end_time_nsec, packets_by_target = collection.target_info
    file_list = build_file_list(targets_and_types, start_time_nsec, end_time_nsec)
    yield packet, topic
  end

  def build_file_list(targets_and_types, start_time_nsec, end_time_nsec)
    list = []
    targets_and_types.each do |target_and_type|
      target_name, cmd_or_tlm, stream_mode = target_and_type.split("__")
      directories = @bucket.list_directories(bucket: ENV['OPENC3_LOGS_BUCKET'], path: "#{@scope}/#{stream_mode.to_s.downcase}_logs/#{cmd_or_tlm.to_s.downcase}/#{target_name}")
      filtered_directories = filter_directories_to_time_range(directories, start_time_nsec, end_time_nsec)
      filtered_directories.each do |directory|
        directory_files = @bucket.list_files()
        files = filter_files_to_time_range(directory_files, start_time_nsec, end_time_nsec)
        list.concat(files)
      end
    end
    return list.sort
  end

  def filter_directories_to_time_range(directories, start_time_nsec, end_time_nsec)
    result = []
    directories.each do |directory|
      result << directory if directory_in_time_range(start_time_nsec, end_time_nsec)
    end
    return result
  end

  def directory_in_time_range(directory, start_time_nsec, end_time_nsec)
    basename = File.basename(directory)
    directory_start_time_nsec = DateTime.strptime(basename, DIRECTORY_TIMESTAMP_FORMAT).to_time.to_nsec_from_epoch
    directory_end_time_nsec = directory_start_time_nsec + NANOSECONDS_PER_DAY
    if (start_time_nsec < directory_end_time_nsec) and (end_time_nsec >= directory_start_time_nsec)
      return true
    else
      return false
    end
  end

  def filter_files_to_time_range(files, start_time_nsec, end_time_nsec)
    result = []
    files.each do |file|
      result << file if file_in_time_range(file, start_time_nsec, end_time_nsec)
    end
    return result
  end

  def file_in_time_range(bucket_path, start_time_nsec, end_time_nsec)
    basename = File.basename(bucket_path)
    file_start_timestamp, file_end_timestamp, other = basename.split("__")
    file_start_time_nsec = DateTime.strptime(file_start_timestamp, FILE_TIMESTAMP_FORMAT).to_time.to_nsec_from_epoch
    file_end_time_nsec = DateTime.strptime(file_end_timestamp, FILE_TIMESTAMP_FORMAT).to_time.to_nsec_from_epoch
    if (start_time_nsec < file_end_time_nsec) and (end_time_nsec >= file_start_time_nsec)
      return true
    else
      return false
    end
  end
end