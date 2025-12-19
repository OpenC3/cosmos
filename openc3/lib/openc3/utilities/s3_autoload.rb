require 'aws-sdk-s3'

if ENV['OPENC3_CLOUD'] == 'local'
  Aws.config.update(
    s3: {
      endpoint: ENV['OPENC3_BUCKET_URL'] || (ENV['OPENC3_DEVEL'] ? 'http://127.0.0.1:9000' : 'http://openc3-s3:9000'),
      access_key_id: ENV['OPENC3_BUCKET_USERNAME'],
      secret_access_key: ENV['OPENC3_BUCKET_PASSWORD'],
      force_path_style: true,
      region: 'us-east-1',
      # Disable automatic checksum calculation for S3-compatible backends (versitygw, minio)
      # that may not support the newer checksum features
      request_checksum_calculation: 'when_required',
      response_checksum_validation: 'when_required',
      # Disable chunked encoding - versitygw has bugs with STREAMING-*-PAYLOAD-TRAILER
      # See: https://github.com/versity/versitygw/issues/1692, #1694, #1695
      disable_request_compression: true
    }
  )
else # AWS
  Aws.config.update(
    s3: {
      endpoint: "https://s3.#{ENV['AWS_REGION']}.amazonaws.com",
      force_path_style: true,
      region: ENV['AWS_REGION']
    }
  )
end
