# Rate limiting for authentication endpoints (Rack::Attack, memory store).
# Wired from config.ru; requires the rack-attack gem (loaded by Bundler).
#
# Thresholds are deliberately generous for a small internal team — they stop
# scripted brute force, not a fumbling human.
class RackAttackConfig
  def self.setup!
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    # Login: 5/min and 30/hour per IP.
    Rack::Attack.throttle('login/ip/min', limit: 5, period: 60) do |req|
      req.ip if req.post? && req.path == '/api/login'
    end
    Rack::Attack.throttle('login/ip/hour', limit: 30, period: 3600) do |req|
      req.ip if req.post? && req.path == '/api/login'
    end

    # Password reset request: 3/hour per IP.
    Rack::Attack.throttle('forgot-password/ip', limit: 3, period: 3600) do |req|
      req.ip if req.post? && req.path == '/api/forgot-password'
    end

    # Self-registration: 5/hour per IP.
    Rack::Attack.throttle('register/ip', limit: 5, period: 3600) do |req|
      req.ip if req.post? && req.path == '/api/register'
    end

    # Public enquiry spam guard: 10/hour per IP.
    Rack::Attack.throttle('public-enquiry/ip', limit: 10, period: 3600) do |req|
      req.ip if req.post? && req.path == '/api/public/enquiries'
    end

    # JSON 429 matching the app's error envelope.
    Rack::Attack.throttled_responder = lambda do |request|
      retry_after = (request.env['rack.attack.match_data'] || {})[:period]
      [429,
       { 'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s },
       [{ status: 'error', data: 'Too many attempts. Please wait a moment and try again.' }.to_json]]
    end
  end
end
