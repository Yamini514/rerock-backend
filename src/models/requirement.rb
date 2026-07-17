class App::Models::Requirement < Sequel::Model
  TRANSACTION_TYPES = %w[buy rent invest].freeze
  URGENCIES         = %w[low medium high].freeze
  STATUSES          = %w[open matched closed].freeze

  many_to_one :customer, class: 'App::Models::Customer', key: :customer_id

  def validate
    super
    validates_presence [:customer_id, :transaction_type, :status]
    validates_includes TRANSACTION_TYPES, :transaction_type, message: 'is not a valid transaction type'
    validates_includes STATUSES, :status, message: 'is not a valid status'
    if budget_min && budget_max && budget_min > budget_max
      errors.add(:budget_min, 'cannot be greater than budget maximum')
    end
    errors.add(:budget_min, 'cannot be negative') if budget_min && budget_min < 0
    errors.add(:budget_max, 'cannot be negative') if budget_max && budget_max < 0
  end

  def to_pos
    as_json
  end
end
