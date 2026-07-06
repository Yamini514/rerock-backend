class App::Models::ActivityLog < Sequel::Model
  ACTIONS = %w[
    create update deactivate login login_failed logout
    password_reset_requested password_reset_completed role_changed
    import export settings_changed
  ].freeze

  # Never write these column values into the changes JSON.
  SENSITIVE_KEYS = %w[encoded_password password reset_token current_session_id].freeze

  many_to_one :user, class: 'App::Models::User', key: :user_id

  def validate
    super
    validates_presence [:action]
    validates_includes ACTIONS, :action, message: 'is not a valid action'
  end

  def to_pos
    as_json.merge('user_name' => user&.full_name)
  end

  # Single write path used by the audit plugin and explicit service calls.
  # Deliberately swallows its own failures (logged) — an audit write must
  # never break the business action it describes.
  def self.record!(action:, entity: nil, changes: nil, details: nil, user: nil)
    u = user || App::Helpers::CurrentUser.user_obj
    clean = changes&.reject { |k, _| SENSITIVE_KEYS.include?(k.to_s) }
    create(
      user_id: u&.id,
      user_email: u&.email,
      action: action.to_s,
      entity_type: entity && entity.class.name.split('::').last,
      entity_id: entity&.pk,
      changes: clean && !clean.empty? ? clean.to_json : nil,
      ip: App::Helpers::CurrentUser.ip,
      details: details
    )
  rescue => e
    App.logger.error("ActivityLog.record! failed: #{e.message}")
    nil
  end
end
