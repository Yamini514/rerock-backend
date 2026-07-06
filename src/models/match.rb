class App::Models::Match < Sequel::Model
  STATUSES = [
    'New', 'Contacted', 'Shortlisted', 'Rejected',
    'Visit Planned', 'Negotiation', 'Closed'
  ].freeze
  SCORE_BANDS = ['High', 'Medium', 'Low', 'Not Recommended'].freeze
  PRIORITIES  = %w[high medium low].freeze

  # Matching Logic Specification (spec section) — weighted criteria, summing to 100.
  WEIGHTS = {
    location: 30, budget: 25, property_type: 15, size: 10,
    intent: 10, urgency: 5, special: 5
  }.freeze

  # Highest-qualifying band wins; below the lowest threshold is "Not Recommended".
  BAND_THRESHOLDS = [['High', 75], ['Medium', 50], ['Low', 25]].freeze

  many_to_one :requirement, class: 'App::Models::Requirement', key: :requirement_id
  many_to_one :property,    class: 'App::Models::Property',    key: :property_id

  def validate
    super
    validates_presence [:requirement_id, :property_id, :status]
    validates_includes STATUSES, :status, message: 'is not a valid status'
    validates_includes SCORE_BANDS, :score_band, message: 'is not a valid score band' if score_band
    validates_unique([:requirement_id, :property_id])

    if %w[Closed Rejected].include?(status) && notes.to_s.strip.empty?
      errors.add(:notes, "is required when a match is marked #{status}")
    end
  end

  # Thresholds default to the code constant but accept configured values
  # (Settings → Matching) as an array of [band, min] pairs sorted high→low.
  def self.band_for(score, thresholds = BAND_THRESHOLDS)
    thresholds.find { |(_, min)| score >= min }&.first || 'Not Recommended'
  end

  def to_pos
    as_json.merge(
      'property_title'    => property&.title,
      'property_location' => property&.location,
      'property_price'    => property&.price,
      'property_image'    => property&.image,
      'customer_name'     => requirement&.customer&.name,
      'customer_id'       => requirement&.customer_id
    )
  end
end
