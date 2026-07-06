class App::Services::Referrals < App::Services::Base
  def model; Referral; end

  # Referrals are a shared team resource (like Members), not per-agent
  # scoped — the spec frames referral management as a company-wide
  # relationship program, not individual agent ownership.
  def list
    ds = model.where(active: true)
    ds = ds.where(member_id: qs[:member_id])         if qs[:member_id].present?
    ds = ds.where(status: qs[:status])                if qs[:status].present?
    ds = ds.where(referral_type: qs[:referral_type])  if qs[:referral_type].present?
    paginate(ds.order(Sequel.desc(:created_at)).eager(:member, :linked_customer, :linked_property))
  end

  def create
    data = data_for(:save)
    # DB column defaults (referral_type/status) aren't applied to a new
    # in-memory instance before validation runs — default them explicitly.
    data['referral_type'] ||= Referral::REFERRAL_TYPES.first
    data['status']        ||= Referral::STATUSES.first
    obj = model.new(data)
    save(obj) do |r|
      r.member.recalculate_tier!
      return_success(r.to_pos)
    end
  end

  def update
    data = data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |r|
      r.member.recalculate_tier!
      return_success(r.to_pos)
    end
  end

  def remove
    member = item.member
    result = super
    member&.recalculate_tier!
    result
  end

  # GET /me/referrals — a member-role user's own referral history + profile.
  # Not staff-gated; any authenticated user with a linked member_id can call this.
  def mine
    u = current_user_obj
    member = u&.member_id && Member[u.member_id]
    return_errors!('No member profile linked to this account.', 404) unless member

    return_success(
      member: member.to_pos,
      referrals: member.referrals_dataset.where(active: true).order(Sequel.desc(:created_at)).all.map(&:to_pos)
    )
  end

  def self.fields
    {
      save: [
        :member_id, :referral_type, :linked_customer_id, :linked_property_id,
        :expected_value, :closure_value, :status, :notes, :date
      ]
    }
  end
end
