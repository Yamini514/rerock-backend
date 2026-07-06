# Generic file upload -> S3, used by the property media gallery (and
# anywhere else that needs to turn a picked file into a public URL).
class App::Services::Uploads < App::Services::Base
  MAX_FILE_SIZE = 10 * 1024 * 1024 # 10MB
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  def create
    files = Array(rp[:files]).compact
    return_errors!('No files provided', 400) if files.empty?

    bucket = ENV['AWS_S3_BUCKET']
    return_errors!('Image storage is not configured (AWS_S3_BUCKET is not set).', 500) if bucket.to_s.strip.empty?

    s3 = Aws::S3::Client.new
    urls = files.map { |file| upload_one(s3, bucket, file) }
    return_success(urls)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  private

  def upload_one(s3, bucket, file)
    tempfile     = file[:tempfile]
    filename     = file[:filename].to_s
    content_type = file[:type] || 'application/octet-stream'

    return_errors!("#{filename}: unsupported file type", 400) unless ALLOWED_TYPES.include?(content_type)
    return_errors!("#{filename}: file is too large (max 10MB)", 400) if tempfile.size > MAX_FILE_SIZE

    key = "uploads/#{Time.now.utc.strftime('%Y/%m')}/#{App.generate_id}#{File.extname(filename)}"
    s3.put_object(bucket: bucket, key: key, body: tempfile, content_type: content_type, acl: 'public-read')

    region = ENV['AWS_REGION'] || 'ap-south-1'
    "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
  end
end
