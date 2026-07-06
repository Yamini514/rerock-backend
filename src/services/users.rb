class App::Services::Users < App::Services::Base
  def model; User; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60 # 2 hours

  def list
    ds = model.where(active: true).order(Sequel.desc(:created_at))
    ds = ds.where(role: qs[:role]) if qs[:role].present?
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:full_name, q),
        Sequel.ilike(:email, q),
        Sequel.ilike(:phone_number, q)
      ))
    end
    paginate(ds)
  end

  def get
    return_success(item.to_pos)
  end

  def create
    check_presence!(:password)
    data = data_for(:save)
    pwd  = data.delete('password')
    validate_password_strength!(pwd)
    obj  = model.new(data)
    obj.password = pwd
    save(obj)
  end

  def update
    data = data_for(:save)
    pwd  = data.delete('password')
    guard_role_or_active_change!(
      item,
      deactivating: [false, 'false'].include?(params[:active]),
      demoting: item.super_admin? && params[:role].present? && params[:role].to_s != 'super_admin'
    )
    if pwd.present?
      validate_password_strength!(pwd)
      item.password = pwd
    end
    item.set_fields(data, data.keys)
    save(item)
  end

  # Soft-deactivate (never hard-delete a user record).
  def remove
    guard_role_or_active_change!(item, deactivating: true, demoting: false)
    super
  end

  # Public self-service registration for portal users (client/member only).
  def register
    role = params[:role].to_s
    return_errors!('Invalid role') unless %w[client member].include?(role)

    email = params[:email].to_s.strip.downcase
    return_errors!('An account with this email already exists.') if model.where(email: email).first

    validate_password_strength!(params[:password])
    u = model.new(
      full_name:    params[:name],
      email:        email,
      phone_number: params[:phone],
      role:         role
    )
    u.password = params[:password]

    save(u) do |user|
      user.current_session_id = CurrentUser.encoded_token(user)
      user.save
      return_success(token: user.current_session_id, info: user.to_pos)
    end
  end

  def info
    return_success(App.cu.user_obj.to_pos)
  end

  # GET /agents — minimal active-staff roster (id/name/role only) for
  # assignment dropdowns. Readable by all staff, unlike the full /users CRUD.
  def agents
    rows = model.where(active: true, role: User::STAFF_ROLES)
                .order(:full_name)
                .select_map([:id, :full_name, :role])
    return_success(rows.map { |(id, name, role)| { id: id, full_name: name, role: role } })
  end

  # Self-service profile edit (any authenticated user) — deliberately limited
  # to name/phone. Email/role changes stay admin-only (see `update` above).
  def update_profile
    u = App.cu.user_obj
    data = params.slice(:full_name, :phone_number)
    u.set_fields(data, data.keys)
    save(u) { return_success(u.to_pos) }
  end

  def update_password
    u = App.cu.user_obj
    if u.password && u.password == params[:current_password].to_s
      validate_password_strength!(params[:new_password])
      u.password = params[:new_password]
      save(u) { return_success("Password updated successfully") }
    else
      return_errors!("Invalid current password")
    end
  end

  def forgot_password
    email = params[:email].to_s.strip.downcase
    return_errors!("Email is required", 400) if email.empty?

    user = model.where(email: email, active: true).first
    if user
      user.generate_reset_token!
      ActivityLog.record!(action: 'password_reset_requested', entity: user, user: user)
      deliver_reset_email(user)
    end
    # Do not reveal whether the email exists.
    return_success("If that email exists, a reset link has been sent.")
  end

  def validate_password_token
    user = token_owner(params[:token])
    user ? return_success("Token is valid.") : return_errors!("Invalid or expired token.")
  end

  def reset_password
    user = token_owner(params[:token])
    return_errors!("Invalid or expired token.", 400) unless user
    return_errors!("Password is required.", 400) if params[:password].to_s.empty?
    validate_password_strength!(params[:password])

    user.password      = params[:password]
    user.reset_token   = nil
    user.reset_sent_at = nil
    save(user) do
      ActivityLog.record!(action: 'password_reset_completed', entity: user, user: user)
      return_success("Password has been reset.")
    end
  end

  def self.fields
    {
      save: [:full_name, :email, :phone_number, :role, :password, :customer_id, :member_id, :active]
    }
  end

  private

  # Password policy is Super-Admin configurable (Settings → Security).
  def validate_password_strength!(pw)
    pw = pw.to_s
    min = AppSetting.get('security.password_min_length', 8).to_i
    issues = []
    issues << "must be at least #{min} characters" if pw.length < min
    if AppSetting.get('security.password_require_mixed', false) == true && !(pw.match?(/[A-Za-z]/) && pw.match?(/\d/))
      issues << 'must include both letters and numbers'
    end
    return_errors!({ password: issues }, 400) unless issues.empty?
  end

  # Prevents a caller from locking themselves out, and prevents the last
  # active Super Admin from being deactivated or demoted.
  def guard_role_or_active_change!(target, deactivating:, demoting:)
    return unless deactivating || demoting

    if target.id == App.cu.user_obj.id
      return_errors!("You can't deactivate or change the role of your own account.", 400)
    end

    if target.super_admin? && model.where(role: 'super_admin', active: true).exclude(id: target.id).count.zero?
      return_errors!('At least one active Super Admin must remain.', 400)
    end
  end

  # Sends the reset link by email (via Notifier + the password_reset
  # template). When SMTP isn't configured or the template is missing, the
  # token still lands in the server log — the original dev behavior.
  def deliver_reset_email(user)
    base = ENV['FRONTEND_URL'].to_s.strip
    base = 'http://localhost:3000' if base.empty? # dev fallback
    link = "#{base}/reset-password?token=#{user.reset_token}"

    log = App::Services::Notifier.dispatch(
      recipient_id: user.id, channel: 'email', template: 'password_reset',
      vars: {
        company_name: AppSetting.get('company.name', 'Rerock Realty'),
        name: user.full_name,
        reset_link: link,
      },
      linked_type: 'User', linked_id: user.id, priority: 'high'
    )
    unless log && log.delivery_status == 'sent'
      App.logger.info("Password reset token for #{user.email}: #{user.reset_token}")
    end
  end

  def token_owner(token)
    return nil if token.to_s.empty?
    user = model.where(reset_token: token).first
    return nil unless user && user.reset_sent_at
    (Time.now - user.reset_sent_at) < RESET_TOKEN_EXPIRATION_TIME ? user : nil
  end
end
