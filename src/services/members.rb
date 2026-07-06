class App::Services::Members < App::Services::Base
  def model; Member; end

  def list
    ds = model.where(active: true)
    ds = ds.where(member_type: qs[:member_type]) if qs[:member_type].present?
    ds = ds.where(status: qs[:status])           if qs[:status].present?
    ds = ds.where(tier: qs[:tier])                if qs[:tier].present?
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:name, q),
        Sequel.ilike(:email, q),
        Sequel.ilike(:phone, q),
        Sequel.ilike(:referral_code, q)
      ))
    end
    ds = ds.order(Sequel.desc(:created_at))
    count = ds.count
    members = ds.offset(offset).limit(limit).all
    stats = referral_stats_for(members.map(&:id))
    return_success(
      members.map { |m| m.to_pos(stats: stats[m.id]) },
      total_pages: (count / page_size.to_f).ceil, total: count
    )
  end

  # DB column defaults (member_type/status) aren't applied to a new in-memory
  # instance before validation runs — default them explicitly here.
  #
  # A `password` is optional: without one this just creates a referral-tracking
  # record. With one, it also provisions a portal login (User, role: 'member',
  # linked via member_id) so the member can sign in at /app/referrals.
  def create
    data = data_for(:save)
    data['member_type'] ||= 'source'
    data['status']      ||= 'active'
    password = data.delete('password')

    member = model.new(data)
    return save(member) if password.blank?

    return_errors!({ email: ["is required to create a login"] }, 400) if member.email.to_s.strip.empty?
    email = member.email.to_s.strip.downcase
    return_errors!({ email: ["is already in use by another account"] }, 400) if User.where(email: email).first

    return_errors!(member.errors, 400) unless member.save

    user = User.new(full_name: member.name, email: email, phone_number: member.phone, role: 'member', member_id: member.id)
    user.password = password
    if user.save
      return_success(member.to_pos)
    else
      member.destroy
      return_errors!(user.errors, 400)
    end
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  # POST /members/recalculate-tiers (super admin) — re-derive every active
  # member's tier from the configured rules (Settings → Elite Tiers).
  def recalculate_tiers
    members = model.where(active: true).all
    members.each(&:recalculate_tier!)
    return_success("Recalculated tiers for #{members.size} member(s).")
  end

  # `tier` is intentionally excluded — it's computed by Member#recalculate_tier!,
  # never set directly by a caller.
  def self.fields
    { save: [:name, :email, :phone, :member_type, :status, :relationship_notes, :password] }
  end

  private

  # Batches what Member#to_pos would otherwise compute with 3 queries PER
  # member (referral_count/converted_count/total_earnings) into 3 queries
  # total for the whole page.
  def referral_stats_for(member_ids)
    return {} if member_ids.empty?
    base = Referral.where(active: true, member_id: member_ids)
    counts = base.group_and_count(:member_id).to_hash(:member_id, :count)

    converted = base.where(status: 'Converted')
    converted_counts = converted.group_and_count(:member_id).to_hash(:member_id, :count)
    earnings = converted
      .select(:member_id)
      .group(:member_id)
      .select_append(Sequel.function(:sum, :closure_value).as(:total))
      .to_hash(:member_id, :total)

    member_ids.each_with_object({}) do |id, h|
      h[id] = {
        referral_count: counts[id] || 0,
        converted_count: converted_counts[id] || 0,
        total_earnings: (earnings[id] || 0).to_i
      }
    end
  end
end
