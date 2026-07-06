class App::Models::AppSetting < Sequel::Model
  VALUE_TYPES = %w[string number boolean json].freeze
  GROUPS      = %w[company branding locale email business matching elite_tiers security general].freeze

  def validate
    super
    validates_presence [:setting_key, :value_type, :group]
    validates_includes VALUE_TYPES, :value_type, message: 'is not a valid value type'
    validates_includes GROUPS, :group, message: 'is not a valid group'
    validates_unique(:setting_key)
  end

  # Typed read of the raw text value.
  def typed_value
    case value_type
    when 'number'  then value.to_s.include?('.') ? value.to_f : value.to_i
    when 'boolean' then value.to_s == 'true'
    when 'json'    then JSON.parse(value.to_s) rescue nil
    else value
    end
  end

  def to_pos
    as_json.merge('typed_value' => typed_value)
  end

  class << self
    # Read a setting with a code-level fallback. Cached in the per-request
    # thread space (cleared by Before.run! each request) so hot paths like
    # match scoring don't re-query per record. NEVER memoize in a class ivar —
    # this class is shared across request threads (see current_user.rb).
    def get(key, default = nil)
      row = cache[key.to_s]
      return default if row.nil? || row.value.nil?
      row.typed_value.nil? ? default : row.typed_value
    end

    # JSON settings often deserialize with string keys; callers that expect
    # symbol keys (e.g. Match weights) get them via deep symbolization.
    def get_json(key, default = nil)
      v = get(key)
      return default unless v
      v.is_a?(Hash) || v.is_a?(Array) ? deep_symbolize(v) : default
    end

    def set(key, value, attrs = {})
      row = where(setting_key: key.to_s).first
      encoded = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
      if row
        row.update({ value: encoded }.merge(attrs))
      else
        row = create({ setting_key: key.to_s, value: encoded, value_type: infer_type(value) }.merge(attrs))
      end
      clear_cache!
      row
    end

    def clear_cache!
      Thread.current[:app_space]&.delete(:app_settings)
    end

    private

    def cache
      space = (Thread.current[:app_space] ||= {})
      space[:app_settings] ||= where(active: true).all.to_h { |s| [s.setting_key, s] }
    end

    def infer_type(value)
      case value
      when Hash, Array then 'json'
      when Numeric     then 'number'
      when true, false then 'boolean'
      else 'string'
      end
    end

    def deep_symbolize(obj)
      case obj
      when Hash  then obj.to_h { |k, v| [k.to_sym, deep_symbolize(v)] }
      when Array then obj.map { |v| deep_symbolize(v) }
      else obj
      end
    end
  end
end
