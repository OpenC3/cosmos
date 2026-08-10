require 'aws-sdk-s3'

if ENV['OPENC3_CLOUD'] == 'local'
  Aws.config.update(
    s3: {
      endpoint: ENV['OPENC3_BUCKET_URL'] || (ENV['OPENC3_DEVEL'] ? 'http://127.0.0.1:9000' : 'http://openc3-buckets:9000'),
      access_key_id: ENV.fetch('OPENC3_BUCKET_USERNAME', nil),
      secret_access_key: ENV.fetch('OPENC3_BUCKET_PASSWORD', nil),
      force_path_style: true,
      region: 'us-east-1',
      # Disable automatic checksum calculation for S3-compatible backends (versitygw)
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
      endpoint: "https://s3.#{ENV.fetch('AWS_REGION')}.amazonaws.com",
      force_path_style: true,
      region: ENV.fetch('AWS_REGION', nil)
    }
  )
end
