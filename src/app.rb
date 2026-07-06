require 'sequel'
require 'logger'
require 'roda'
require 'aws-sdk-s3'
module App
  class<<self
    attr_reader :db, :audit_db

    def development?
      env == 'development'
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def env
      @env ||= ENV['RACK_ENV'] || 'development'
    end

    def root
      @root ||= File.expand_path(File.dirname(__FILE__) + '/../')
    end

    def require_blob(blb)
      Dir[File.join(root, 'src', blb)].each {|f| require f}
    end

    # Dependency-free .env loader. Populates ENV from <root>/.env without
    # overriding variables already set in the real environment (e.g. Fly.io
    # secrets in production). Keeps all secrets out of source files.
    def load_env!
      return if @env_loaded
      @env_loaded = true
      path = File.join(root, '.env')
      return unless File.exist?(path)
      File.foreach(path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        key, _sep, val = line.partition('=')
        key = key.strip
        next if key.empty?
        val = val.strip.gsub(/\A["']|["']\z/, '')
        ENV[key] ||= val
      end
    end

    def db_url
      load_env!
      ENV['DB_URL'] || raise("DB_URL is not set. Copy .env.example to .env and set DB_URL.")
    end

    def jwt_secret
      load_env!
      ENV['JWT_SECRET'] || raise("JWT_SECRET is not set. Copy .env.example to .env and set JWT_SECRET.")
    end

    # Must be resolved lazily (after load_env!) and must at least match the
    # server's thread count: with a pool smaller than Puma's threads, a burst
    # of concurrent requests makes the losers wait 5s for a connection, hit
    # Sequel::PoolTimeout inside the auth check, and get 401'd with a valid
    # token — the frontend then logs the user out as "signed in elsewhere".
    def pool_size
      load_env!
      (ENV['POOL_SIZE'] || 10).to_i
    end

    def load!
      # Load environment variables first so everything below can rely on ENV
      load_env!

      # First connect to the database
      connect_to_database
      
      # Load libraries before models
      require_blob('lib/**/*.rb')
      
      # Setup Sequel configuration
      setup_sequel!
      
      # Load helpers before models
      App.require_blob('helpers/*.rb')
      
      # Load models in the correct order
      require_blob('models/concerns/*.rb')
      require_blob('models/*.rb')
      require_blob('models/**/*.rb')
      
      # Load routes last
      require_relative 'routes'

      # Configure AWS with environment variables
      setup_aws_config
    end

    def connect_to_database
      @db = Sequel.connect(db_url,
        max_connections: pool_size,
        logger: logger, 
        after_connect: Proc.new { logger.info("Database connection established") }
      )
      @db.extension(:connection_validator)
      @db.pool.connection_validation_timeout = 3600
    end
    
    def setup_aws_config
      # Use environment variables instead of hardcoded credentials
      aws_access_key = ENV['AWS_ACCESS_KEY_ID']
      aws_secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      aws_region = ENV['AWS_REGION'] || 'ap-south-1'
      
      Aws.config.update(
        region: aws_region,
        credentials: Aws::Credentials.new(aws_access_key, aws_secret_key),
      )
      
      logger.info("AWS configuration initialized for region: #{aws_region}")
    end

    def cu
      App::Helpers::CurrentUser
    end

    def generate_id
      Time.now.utc.strftime("%Y%m%d%H%M%S%N").to_i.to_s(36)
    end

    def setup_sequel!
      Sequel::Model.plugin :validation_helpers
      Sequel::Model.plugin :force_encoding, 'UTF-8'
      Sequel::Model.plugin(::SequelPlugin::SaveUserId)
      # Sequel::Model.plugin(::SequelPlugin::JsonValuesValidations)
      # Sequel::Model.plugin(::SequelPlugin::JsonValueTypecast)
      Sequel::Model.plugin(::SequelPlugin::DefaultJson)
      Sequel::Model.plugin :nested_attributes
      Sequel::Model.plugin :dirty
      # AuditLog reads `previous_changes` in after_update, which the dirty
      # plugin populates in its own after_update — AuditLog must be registered
      # AFTER :dirty so dirty's hook (closer to the class in the MRO) has
      # already assigned it by the time AuditLog's hook runs.
      Sequel::Model.plugin(::SequelPlugin::AuditLog)
      Sequel::Model.plugin :json_serializer
      Sequel::Model.raise_on_save_failure = false
      Sequel.extension :core_extensions
      Sequel.extension :named_timezones
      Sequel.extension :pg_json_ops
      Sequel.extension :pg_array_ops
      db.extension :pg_json, :pg_array, :pg_enum
      db.wrap_json_primitives = true
      db.typecast_json_strings = true
    end
  end

  module Models
  end
  module Services
  end
  module Helpers; end
  module Router; end
end

# db_url = "postgres://appadmin:dev123@172.16.169.228:5432/lnhtywgf"



# postgres://qxkzecte:7KET4hfRlDfexuBw7DnXm2mTFdXILqoG@satao.db.elephantsql.com/qxkzecte

# max_id = DB[:users].max(:id)

# # Set the sequence to the maximum id + 1
# DB.run("SELECT setval(pg_get_serial_sequence('users', 'id'), #{max_id + 1})")