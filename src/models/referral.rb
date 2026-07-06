class App::Models::Referral < Sequel::Model
  REFERRAL_TYPES = %w[buyer seller investor property].freeze
  STATUSES = [
    'New', 'Reviewed', 'Contacted', 'Qualified', 'In Progress',
    'Converted', 'Rejected', 'Duplicate'
  ].freeze

  many_to_one :member, class: 'App::Models::Member', key: :member_id
  many_to_one :linked_customer, class: 'App::Models::Customer', key: :linked_customer_id
  many_to_one :linked_property, class: 'App::Models::Property', key: :linked_property_id

  def validate
    super
    validates_presence [:member_id, :referral_type, :status]
    # Referral types/sources are master-data driven (Super Admin configurable).
    validates_includes App::Models::MasterDataItem.values_for(:referral_sources, fallback: REFERRAL_TYPES),
                       :referral_type, message: 'is not a valid referral type'
    validates_includes STATUSES, :status, message: 'is not a valid status'

    [:expected_value, :closure_value].each do |f|
      v = send(f)
      errors.add(f, 'must be numeric') if v && !v.is_a?(Numeric)
    end

    if status == 'Converted' && notes.to_s.strip.empty?
      errors.add(:notes, 'is required when a referral is marked Converted')
    end
  end

  def to_pos
    as_json.merge(
      'member_name' => member&.name,
      'customer_name' => linked_customer&.name,
      'property_title' => linked_property&.title
    )
  end
end
