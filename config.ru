require 'bundler'
require 'open-uri'
require 'csv'
Rack::Utils # Patch
require './src/app'

Bundler.require(:default, App.env)


# CORS: locked to ALLOWED_ORIGINS (comma-separated) in production; '*' only
# as the dev fallback when the variable isn't set.
App.load_env!
allowed_origins = ENV['ALLOWED_ORIGINS'].to_s.split(',').map(&:strip).reject(&:empty?)
allowed_origins = ['*'] if allowed_origins.empty?

use Rack::Cors do
  allow do
    origins(*allowed_origins)
    resource '*', :headers => :any, :methods => [:get, :post, :delete, :put, :patch, :options, :head]
  end
end

# Brute-force protection on auth + public endpoints.
require './src/lib/rack_attack_config'
RackAttackConfig.setup!
use Rack::Attack

App.load!

run App::Routes

if App.development?
  Listen.to(File.expand_path(File.dirname(__FILE__)), only: %r{.rb$}) do |added, modified, removed|
    files_to_reload = added + modified
    
    App.logger.info("Reloading: #{files_to_reload.join(', ')}")
    
    # Handle route file specially to ensure proper reloading
    if files_to_reload.any? { |f| f.include?('routes.rb') }
      App.logger.info("Routes file changed, consider restarting the server for full effect")
      # Optionally implement more sophisticated routes reloading here
    end
    
    # Reload all changed files
    files_to_reload.each do |f|
      begin
        load(f)
        App.logger.info("Successfully reloaded: #{f}")
      rescue => e
        App.logger.error("Error reloading #{f}: #{e.message}")
        App.logger.error(e.backtrace.join("\n"))
      end
    end
  end.start
end
