class App::Models::Customer < Sequel::Model
  LEAD_TYPES = %w[buyer seller investor tenant owner enquiry].freeze
  STATUSES   = %w[new contacted qualified shortlisted visit_planned
                  negotiation closed lost on_hold].freeze

  one_to_many :requirements, class: 'App::Models::Requirement', key: :customer_id, order: Sequel.desc(:created_at)
  many_to_one :assigned_user, class: 'App::Models::User', key: :assigned_user_id

  def validate
    super
    validates_presence [:name, :phone, :lead_type, :status]
    validates_includes LEAD_TYPES, :lead_type, message: 'is not a valid lead type'
    # Status list is master-data driven (Super Admin configurable).
    validates_includes App::Models::MasterDataItem.values_for(:customer_statuses, fallback: STATUSES),
                       :status, message: 'is not a valid status'
  end

  def before_save
    self.email = email.to_s.strip.downcase if email.present?
    super
  end

  def to_pos
    reqs = requirements
    as_json.merge(
      'assigned_agent'      => assigned_user&.full_name,
      'requirements'        => reqs.map(&:to_pos),
      'primary_requirement' => reqs.first&.to_pos,
      'enquiries'           => reqs.length
    )
  end
end
