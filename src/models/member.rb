class App::Models::Member < Sequel::Model
  MEMBER_TYPES = %w[buyer seller investor source].freeze
  STATUSES     = %w[active inactive].freeze
  TIERS        = %w[Standard Silver Gold Elite].freeze

  # Spec leaves exact thresholds open ("configurable"); these are sensible
  # defaults to adjust once real referral volume is observed. Checked from
  # highest tier down — the first rule a member qualifies for (by count OR
  # value) wins.
  TIER_RULES = [
    ['Elite',  16, 500_000],
    ['Gold',    8, 200_000],
    ['Silver',  3,  50_000],
  ].freeze

  one_to_many :referrals, class: 'App::Models::Referral', key: :member_id, order: Sequel.desc(:created_at)

  def validate
    super
    validates_presence [:name, :phone, :member_type, :status]
    # Member types are master-data driven (Super Admin configurable).
    validates_includes App::Models::MasterDataItem.values_for(:member_types, fallback: MEMBER_TYPES),
                       :member_type, message: 'is not a valid member type'
    validates_includes STATUSES, :status, message: 'is not a valid status'
    validates_unique(:referral_code)
  end

  def before_validation
    self.referral_code = generate_referral_code if referral_code.nil? || referral_code.to_s.strip.empty?
    # `tier` is never caller-set (excluded from the service's writable
    # fields) — it must still get an initial value before the first save.
    self.tier ||= 'Standard'
    super
  end

  def generate_referral_code
    "MRK-#{App.generate_id.upcase}"
  end

  def referral_count
    referrals_dataset.where(active: true).count
  end

  def converted_count
    referrals_dataset.where(active: true, status: 'Converted').count
  end

  def total_earnings
    referrals_dataset.where(active: true, status: 'Converted').sum(:closure_value).to_i
  end

  # Tier rules are Super-Admin configurable (Settings → Elite Tiers), stored
  # as [{tier:, min_count:, min_value:}] ordered highest first; TIER_RULES
  # remains the fallback for an unseeded database.
  def self.tier_rules
    rules = App::Models::AppSetting.get_json('elite_tiers.rules', nil)
    return TIER_RULES unless rules.is_a?(Array) && !rules.empty?
    rules.map { |r| [r[:tier].to_s, r[:min_count].to_i, r[:min_value].to_i] }
  end

  # Called by ReferralsService after any referral create/update/deactivate
  # affecting this member, so the tier always reflects current standing.
  def recalculate_tier!
    count = referral_count
    value = total_earnings
    new_tier = self.class.tier_rules.find { |(_, min_count, min_value)| count >= min_count || value >= min_value }&.first || 'Standard'
    update(tier: new_tier) unless tier == new_tier
  end

  # `stats:` lets a batch list endpoint pass in precomputed aggregates
  # (see Members#referral_stats_for) instead of this running 3 queries per
  # row; a standalone `member.to_pos` (e.g. GET /members/:id) still works
  # unchanged by falling back to the per-record queries below.
  def to_pos(stats: nil)
    s = stats || { referral_count: referral_count, converted_count: converted_count, total_earnings: total_earnings }
    as_json.merge(
      'referral_count'  => s[:referral_count],
      'converted_count' => s[:converted_count],
      'total_earnings'  => s[:total_earnings]
    )
  end
end
