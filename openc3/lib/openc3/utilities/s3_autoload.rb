require 'aws-sdk-s3'

Aws.config.update(
  s3: {
    endpoint: ENV['OPENC3_BUCKET_URL'] || (ENV['OPENC3_DEVEL'] ? 'http://127.0.0.1:9000' : 'http://openc3-minio:9000'),
    access_key_id: ENV['OPENC3_BUCKET_USERNAME'],
    secret_access_key: ENV['OPENC3_BUCKET_PASSWORD'],
    force_path_style: true,
    region: 'us-east-1'
  }
)