require 'active_support/core_ext/integer/time'
require 'active_support/core_ext/object/blank'
class App::Helpers::CurrentUser
  TOKEN_EXPIRY = 180.hours # Extracted as a constant for easier management

  class<<self
    def secret
      App.jwt_secret
    end

    def id
      decoded_token&.[](:id)
    end

    def role
      decoded_token&.[](:role)
    end

    def valid?
      return false if id.blank? || user_obj.nil?
      
      # Check if token matches and is not expired
      user_obj.current_session_id == token
    end

    def ip
      space[:ip]
    end

    def space
      Thread.current[:app_space] || {}
    end

    def current_did
      space[:did]
    end

    def token
      return nil if space.nil? || space[:auth_token].blank?

      # Memoize in the per-request thread space, NEVER in a class-level
      # @token ivar: this class is a singleton shared by every request in
      # the process, so a class-level memo pins the first request's token
      # forever. Symptom: the first login after boot works, then any new
      # login rotates current_session_id and every later request is
      # validated against the stale pinned token -> permanent 401s.
      space[:token] ||= space[:auth_token].gsub("Bearer ", "")
    end

    def decoded_token
      return nil if token.nil?

      space[:decoded] ||= begin
        decoded = JWT.decode(token, secret, true, { algorithm: 'HS256' })[0].with_indifferent_access
        
        # Check token expiration
        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("Token expired for user #{decoded[:id]}")
          return nil
        end
        
        decoded
      rescue JWT::DecodeError => e
        App.logger.error("JWT decode error: #{e.message}")
        nil
      rescue => e
        App.logger.error("Token decode error: #{e.message}")
        nil
      end
    end

    def user_obj
      return nil if id.blank?
      
      space[:user_obj] ||= begin
        # `.where(...)[id]` is Dataset#[], which treats a bare Integer as a
        # row-count LIMIT, not a primary-key filter — it silently returned
        # the wrong thing (an array of up to `id` rows) instead of "the
        # user with this id", breaking every auth check. Filter explicitly.
        #
        # No blanket rescue here: a DB error (e.g. Sequel::PoolTimeout under
        # load) must surface as a 500, not be swallowed into nil — nil means
        # "no such user", which auth turns into a 401 that logs the user out.
        user = App::Models::User.where(active: true, id: id).first
        App.logger.warn("User not found or inactive: #{id}") if user.nil?
        user
      end
    end

    def basic_info
      return {} if user_obj.nil?
      
      user_obj.values.slice(:email, :first_name, :last_name, :role)
    end

    def admin?
      user_obj&.role === 0
    end

    def entity_ids
      user_obj&.entity_ids || []
    end

    def encoded_token(user)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { 
        id: user.id, 
        role: user.role, 
        ip: ip, 
        exp: exp,
        iat: Time.now.to_i # Added issued at timestamp
      }
      JWT.encode(payload, secret, 'HS256')
    end
    
    def clear_cache!
      space.delete(:decoded)
      space.delete(:user_obj)
      space.delete(:token)
    end
  end

  # Removed commented code
end