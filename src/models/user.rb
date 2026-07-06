require 'bcrypt'
class App::Models::User < Sequel::Model
  include BCrypt

  # Roles align with the frontend route guards:
  #   super_admin / admin / agent / property_manager /
  #   referral_coordinator / viewer -> internal admin console (/admin)
  #   client / member               -> public portal (/app)
  #
  # SRS role mapping:
  #   admin                -> Business Owner / Principal
  #   agent                -> Sales / Relationship Manager
  #   property_manager     -> Property Manager (property-focused access)
  #   referral_coordinator -> Referral Coordinator (member/referral-focused)
  #   viewer               -> Read-only Viewer (reads everything staff can, writes nothing)
  ROLES       = %w[super_admin admin agent property_manager referral_coordinator viewer client member].freeze
  STAFF_ROLES = %w[super_admin admin agent property_manager referral_coordinator viewer].freeze

  one_to_many :assigned_customers,  class: 'App::Models::Customer', key: :assigned_user_id
  one_to_many :assigned_properties, class: 'App::Models::Property', key: :assigned_user_id

  def validate
    super
    validates_presence [:full_name, :email, :role]
    validates_includes ROLES, :role, message: 'is not a valid role'
    validates_format(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, :email, message: 'is not a valid email')
    validates_unique(:email)
  end

  def before_save
    self.email = email.to_s.strip.downcase if email
    super
  end

  # --- Password (bcrypt) ---
  def password
    @password ||= Password.new(encoded_password) if encoded_password.present?
  end

  def password=(new_password)
    return if new_password.nil? || new_password.to_s.empty?
    @password = Password.create(new_password)
    self.encoded_password = @password
  end

  # --- Role helpers ---
  def super_admin?; role == 'super_admin'; end
  def admin?;  role == 'admin';  end
  def agent?;  role == 'agent';  end
  def property_manager?;     role == 'property_manager';     end
  def referral_coordinator?; role == 'referral_coordinator'; end
  def viewer?; role == 'viewer'; end
  def staff?;  STAFF_ROLES.include?(role); end
  # Legacy hook referenced by the template router/auth helper.
  def rgm?;    false; end

  # --- Password reset ---
  def generate_reset_token!
    self.reset_token   = SecureRandom.urlsafe_base64
    self.reset_sent_at = Time.now
    save
  end

  # Safe representation returned to clients (never exposes the password hash).
  def to_pos
    as_json(only: [
      :id, :full_name, :email, :phone_number, :role,
      :customer_id, :member_id, :active, :last_logged_in_at,
      :created_at, :updated_at
    ])
  end

  # Auth payload (same shape; kept as a distinct name for call sites).
  def as_pos
    to_pos
  end
end
