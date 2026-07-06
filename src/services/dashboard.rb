class App::Services::Dashboard < App::Services::Base
  # No `model` — this service only aggregates across other tables.

  PROPERTY_TYPE_COLORS = {
    'Apartment' => '#6366f1', 'Villa' => '#8b5cf6', 'Studio' => '#ec4899',
    'Penthouse' => '#f59e0b', 'Commercial' => '#10b981', 'Plot' => '#14b8a6',
  }.freeze

  # GET /dashboard/overview. Every metric goes through the same role scoping
  # as the corresponding list page: agents see their own (assigned + shared)
  # numbers; all other staff see company-wide figures.
  def overview
    return_success(
      stats: [
        stat_card('Total Properties', scope_to_assigned(Property.where(active: true)).count, :properties),
        stat_card('Active Clients', scope_to_assigned(Customer.where(active: true).exclude(status: %w[closed lost])).count, :customers),
        stat_card('Open Enquiries', scope_to_assigned(Match.where(active: true).exclude(status: %w[Closed Rejected])).count, :matches),
        stat_card('Deals This Month', deals_this_month, :deals),
        stat_card('Follow-ups Due', due_follow_ups_count, :followups),
      ],
      monthly: monthly_enquiries,
      by_type: property_type_breakdown,
      activity: recent_activity
    )
  end

  # GET /dashboard/properties
  def properties
    ds = scope_to_assigned(Property.where(active: true))
    return_success(
      total: ds.count,
      by_status: ds.group_and_count(:status).all.map { |r| { status: r[:status], count: r[:count] } },
      by_type: ds.group_and_count(:property_type).all.map { |r| { type: r[:property_type], count: r[:count] } }
    )
  end

  # GET /dashboard/customers
  def customers
    ds = scope_to_assigned(Customer.where(active: true))
    return_success(
      total: ds.count,
      by_status: ds.group_and_count(:status).all.map { |r| { status: r[:status], count: r[:count] } }
    )
  end

  # GET /dashboard/referrals
  def referrals
    ds = Referral.where(active: true)
    return_success(
      total_members: Member.where(active: true).count,
      total_referrals: ds.count,
      converted: ds.where(status: 'Converted').count,
      total_earnings_paid: ds.where(status: 'Converted').sum(:closure_value).to_i,
      by_tier: Member.where(active: true).group_and_count(:tier).all.map { |r| { tier: r[:tier], count: r[:count] } }
    )
  end

  # GET /dashboard/matches
  def matches
    ds = scope_to_assigned(Match.where(active: true))
    return_success(
      total: ds.count,
      by_band: ds.exclude(score_band: nil).group_and_count(:score_band).all.map { |r| { band: r[:score_band], count: r[:count] } },
      by_status: ds.group_and_count(:status).all.map { |r| { status: r[:status], count: r[:count] } },
      pending_contact: ds.where(status: 'New').count,
      closed: ds.where(status: 'Closed').count
    )
  end

  # GET /dashboard/follow-ups. FollowUp scopes by owner_id, not
  # assigned_user_id — agents see their own tasks only, and the by-owner
  # breakdown (other staff's workloads) is withheld from them.
  def follow_ups
    ds = FollowUp.where(active: true)
    ds = ds.where(owner_id: current_user_obj.id) if current_user_obj&.agent?
    today_start = Date.today.to_time
    today_end   = (Date.today + 1).to_time
    return_success(
      due_today: ds.where(status: 'pending', due_date: today_start...today_end).count,
      overdue: ds.where(status: 'pending').where(Sequel.expr(:due_date) < today_start).count,
      completed: ds.where(status: 'completed').count,
      by_owner: ds.where(status: 'pending').group_and_count(:owner_id).all.map { |r| { owner_id: r[:owner_id], count: r[:count] } }
    )
  end

  private

  def stat_card(label, value, kind)
    { label: label, value: value.to_s, icon: icon_for(kind), color: color_for(kind) }
  end

  def icon_for(kind)
    { properties: 'Building2', customers: 'Users', matches: 'MessageSquare', deals: 'TrendingUp', followups: 'CalendarClock' }[kind]
  end

  def color_for(kind)
    { properties: 'indigo', customers: 'violet', matches: 'blue', deals: 'emerald', followups: 'rose' }[kind]
  end

  # Pending items due today or already overdue — combines the two counts the
  # dedicated /dashboard/follow-ups endpoint reports separately, in one query.
  def due_follow_ups_count
    tomorrow_start = (Date.today + 1).to_time
    ds = FollowUp.where(active: true, status: 'pending').where(Sequel.expr(:due_date) < tomorrow_start)
    ds = ds.where(owner_id: current_user_obj.id) if current_user_obj&.agent?
    ds.count
  end

  def deals_this_month
    start_of_month = Date.today.beginning_of_month.to_time
    closed_matches = scope_to_assigned(Match.where(active: true, status: 'Closed'))
                       .where(Sequel.expr(:updated_at) >= start_of_month).count
    # Referral earnings are outside the agent's scope (route also denies
    # /dashboard/referrals to agents) — count them for everyone else.
    return closed_matches if current_user_obj&.agent?
    closed_matches +
      Referral.where(active: true, status: 'Converted').where(Sequel.expr(:created_at) >= start_of_month).count
  end

  # Last 6 months of Match volume vs. how many closed, for the trend chart.
  def monthly_enquiries
    (0..5).to_a.reverse.map do |months_ago|
      month_start = (Date.today << months_ago).beginning_of_month
      month_end   = month_start.next_month
      scope = scope_to_assigned(Match.where(active: true)).where(created_at: month_start.to_time...month_end.to_time)
      {
        month: month_start.strftime('%b'),
        enquiries: scope.count,
        conversions: scope.where(status: 'Closed').count
      }
    end
  end

  def property_type_breakdown
    ds = scope_to_assigned(Property.where(active: true))
    total = ds.count
    return [] if total.zero?
    ds.group_and_count(:property_type).all.map do |r|
      {
        name: r[:property_type],
        value: ((r[:count] / total.to_f) * 100).round,
        color: PROPERTY_TYPE_COLORS[r[:property_type]] || '#94a3b8'
      }
    end
  end

  # Most recent create/update across the entities staff care about, merged
  # and sorted — there's no single table to query this from directly.
  # Agent view: own customers/properties/matches only, and no referral feed
  # (other agents' client names must not leak — audit finding).
  def recent_activity
    agent = current_user_obj&.agent?
    items = []
    scope_to_assigned(Customer.where(active: true)).order(Sequel.desc(:created_at)).limit(5).each do |c|
      items << { type: 'client', action: "New client registered: #{c.name}", user: c.name, at: c.created_at }
    end
    scope_to_assigned(Property.where(active: true)).order(Sequel.desc(:created_at)).limit(5).each do |p|
      items << { type: 'property', action: "New listing: #{p.title}", user: p.assigned_user&.full_name, at: p.created_at }
    end
    unless agent
      Referral.where(active: true).order(Sequel.desc(:created_at)).limit(5).each do |r|
        items << { type: 'referral', action: "New referral logged by #{r.member&.name}", user: r.member&.name, at: r.created_at }
      end
    end
    scope_to_assigned(Match.where(active: true)).order(Sequel.desc(:updated_at)).limit(5).each do |m|
      items << { type: 'enquiry', action: "Match status changed to #{m.status}", user: nil, at: m.updated_at }
    end
    items.sort_by { |i| i[:at] || Time.at(0) }.reverse.first(10).map.with_index do |i, idx|
      i.merge(id: idx + 1, time: relative_time(i[:at]))
    end
  end

  def relative_time(time)
    return '' unless time
    diff = Time.now - time
    return 'Just now' if diff < 60
    return "#{(diff / 60).floor}m ago" if diff < 3600
    return "#{(diff / 3600).floor}h ago" if diff < 86_400
    "#{(diff / 86_400).floor}d ago"
  end
end
