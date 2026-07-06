class App::Models::MasterDataItem < Sequel::Model
  CATEGORIES = %w[
    property_types locations lead_sources referral_sources member_types
    property_statuses customer_statuses followup_statuses tags
  ].freeze

  def validate
    super
    validates_presence [:category, :value, :label]
    validates_includes CATEGORIES, :category, message: 'is not a valid category'
    validates_unique([:category, :value])

    # System rows back code logic (e.g. property 'sold', customer 'closed') —
    # renaming their stored value would orphan existing records and break
    # scoring/dashboard queries. They can only be relabelled or deactivated.
    if !new? && is_system && column_changed?(:value)
      errors.add(:value, 'cannot be changed on a system entry')
    end
  end

  def before_validation
    self.value = value.to_s.strip if value
    self.label = label.to_s.strip if label
    super
  end

  class << self
    # Active values for a category, used by model enum validation. Falls back
    # to the legacy model constant when the table/category is empty (e.g. an
    # environment where the migration ran but seeds didn't), so validation can
    # never lock out every value. Cached per request in the thread space.
    def values_for(category, fallback: [])
      vals = cache[category.to_s] || []
      vals.empty? ? fallback : vals
    end

    def clear_cache!
      Thread.current[:app_space]&.delete(:master_data_values)
    end

    private

    def cache
      space = (Thread.current[:app_space] ||= {})
      space[:master_data_values] ||= where(active: true)
        .order(:sort_order, :label)
        .select_map([:category, :value])
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
