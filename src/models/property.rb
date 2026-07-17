class App::Models::Property < Sequel::Model
  PROPERTY_TYPES    = %w[Apartment Villa Studio Penthouse Commercial Plot].freeze
  TRANSACTION_TYPES = %w[buy rent].freeze
  STATUSES          = %w[draft available under_discussion blocked sold inactive].freeze

  # Owner/source fields are confidential and hidden from non-staff callers.
  CONFIDENTIAL_FIELDS = %w[owner_name owner_contact source_member_id source_notes notes].freeze

  many_to_one :assigned_user, class: 'App::Models::User', key: :assigned_user_id

  def validate
    super
    validates_presence [:code, :title, :property_type, :location, :transaction_type, :status]
    # Enum values are master-data driven (Super Admin configurable); the old
    # constants remain as the seed source and fallback for unseeded databases.
    validates_includes App::Models::MasterDataItem.values_for(:property_types, fallback: PROPERTY_TYPES),
                       :property_type, message: 'is not a valid property type'
    validates_includes App::Models::MasterDataItem.values_for(:property_statuses, fallback: STATUSES),
                       :status, message: 'is not a valid status'
    validates_unique(:code)
    %i[price area bedrooms bathrooms].each do |field|
      value = send(field)
      errors.add(field, 'cannot be negative') if value && value < 0
    end
  end

  def before_validation
    self.code = generate_code if code.nil? || code.to_s.strip.empty?
    super
  end

  def generate_code
    "MRK-#{App.generate_id.upcase}"
  end

  def to_pos
    h = as_json.merge('agent' => assigned_user&.full_name)
    user = App::Helpers::CurrentUser.user_obj
    # `confidential` records are Super-Admin-only; otherwise any staff member
    # (admin/agent) can see owner/source fields, but client/member never can.
    should_mask = confidential ? !user&.super_admin? : !user&.staff?
    CONFIDENTIAL_FIELDS.each { |f| h.delete(f) } if should_mask
    h
  end
end
