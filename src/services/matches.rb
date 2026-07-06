class App::Services::Matches < App::Services::Base
  def model; Match; end

  def list
    ds = model.where(active: true)
    ds = ds.where(status: qs[:status])           if qs[:status].present?
    ds = ds.where(score_band: qs[:score_band])   if qs[:score_band].present?
    ds = ds.where(requirement_id: qs[:requirement_id]) if qs[:requirement_id].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    if qs[:min_score].present?
      # Hoisted local: zero-arity where{} blocks are instance_exec'd against
      # VirtualRow, where `qs` would not resolve to the service method.
      min = qs[:min_score].to_i
      ds = ds.where { score >= min }
    end
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      prop_ids = Property.where(Sequel.ilike(:title, q)).select(:id)
      req_ids  = Requirement.where(customer_id: Customer.where(Sequel.ilike(:name, q)).select(:id)).select(:id)
      ds = ds.where(Sequel.|({ property_id: prop_ids }, { requirement_id: req_ids }))
    end
    paginate(scope_to_assigned(ds).order(*sort_order).eager(:property, requirement: :customer))
  end

  # PUT /matches/bulk — { data: { ids: [], status:, notes: } }. Notes are
  # required by the model when the status is Closed/Rejected; a row that
  # fails validation is reported, not silently skipped.
  def bulk_update
    ids    = Array(params[:ids]).map(&:to_i).reject(&:zero?)
    status = params[:status].to_s
    return_errors!('No match ids given', 400) if ids.empty?
    return_errors!('is not a valid status', 400) unless Match::STATUSES.include?(status)

    updated, failed = 0, []
    model.where(active: true, id: ids).all.each do |m|
      m.status = status
      m.notes  = params[:notes] if params[:notes].present?
      m.save ? updated += 1 : failed << { id: m.id, errors: m.errors }
    end
    return_success({ updated: updated, failed: failed })
  end

  # Manually log an "enquiry" — a customer's specific interest in a property,
  # entered by staff rather than suggested by the scoring engine. No score.
  def create
    data = data_for(:save)
    u = current_user_obj
    data['assigned_user_id'] = u.id if u&.agent? && data['assigned_user_id'].blank?
    # DB column defaults (status/priority) aren't applied to a new in-memory
    # instance before validation runs — default them explicitly.
    data['status']   ||= Match::STATUSES.first
    data['priority'] ||= 'medium'
    save(model.new(data))
  end

  def update
    data = data_for(:save)
    item.set_fields(data, data.keys)
    save(item)
  end

  # Score every active/open requirement against every active, sellable
  # property, upserting a Match row per pair (spec: "Buyer to Property" /
  # "Property to Buyer" / weighted scoring criteria).
  def recalculate
    requirements = Requirement.where(active: true, status: 'open').all
    properties   = Property.where(active: true).exclude(status: %w[sold inactive]).all

    scored = score_pairs(requirements, properties)

    return_success("Scored #{requirements.size} requirement(s) against #{properties.size} propert#{properties.size == 1 ? 'y' : 'ies'} (#{scored} pairs evaluated).")
  end

  # ── Targeted auto-rescore hooks (Settings → Matching → auto-recalculate) ──
  # Called by Properties/Requirements after a save. Deliberately swallow
  # errors: a scoring failure must never break the save that triggered it.

  def rescore_property!(prop)
    return unless auto_recalculate?
    return unless prop.active && !%w[sold inactive].include?(prop.status)
    score_pairs(Requirement.where(active: true, status: 'open').all, [prop])
  rescue => e
    App.logger.error("Auto-rescore (property #{prop.id}) failed: #{e.message}")
  end

  def rescore_requirement!(req)
    return unless auto_recalculate?
    return unless req.active && req.status == 'open'
    score_pairs([req], Property.where(active: true).exclude(status: %w[sold inactive]).all)
  rescue => e
    App.logger.error("Auto-rescore (requirement #{req.id}) failed: #{e.message}")
  end

  def self.fields
    {
      save: [
        :requirement_id, :property_id, :status, :priority,
        :next_followup_at, :notes, :assigned_user_id
      ]
    }
  end

  private

  # Whitelisted sort for the matching dashboard (?sort=score&dir=asc);
  # defaults to newest first, with score ties broken by recency.
  def sort_order
    dir = qs[:dir].to_s == 'asc' ? :asc : :desc
    case qs[:sort].to_s
    when 'score'
      # Manual enquiries have no score — keep them after scored matches.
      [Sequel.send(dir, :score, nulls: :last), Sequel.desc(:created_at)]
    else
      [Sequel.send(dir, :created_at)]
    end
  end

  # ── Configurable engine parameters (Settings → Matching) ──
  # Read once per request (AppSetting caches in the request thread space);
  # every getter falls back to the code constants so an unseeded database
  # behaves exactly as before.

  def weights
    @weights ||= begin
      w = AppSetting.get_json('matching.weights', nil)
      w.is_a?(Hash) && !w.empty? ? Match::WEIGHTS.merge(w) : Match::WEIGHTS
    end
  end

  def band_thresholds
    @band_thresholds ||= begin
      bands = AppSetting.get_json('matching.score_bands', nil)
      if bands.is_a?(Hash) && !bands.empty?
        bands.map { |band, min| [band.to_s, min.to_i] }.sort_by { |(_, min)| -min }
      else
        Match::BAND_THRESHOLDS
      end
    end
  end

  def min_score
    @min_score ||= AppSetting.get('matching.min_score', 25).to_i
  end

  def auto_recalculate?
    AppSetting.get('matching.auto_recalculate', false) == true
  end

  # Shared upsert loop used by full and targeted recalculation.
  def score_pairs(requirements, properties)
    scored = 0
    requirements.each do |req|
      properties.each do |prop|
        score = compute_score(req, prop)
        # Scoped to active: true — a soft-deactivated match at this same pair
        # is left alone (recreating it would hit the unique index; the rare
        # deactivate-then-rescan case is left as a known limitation).
        existing = Match.where(requirement_id: req.id, property_id: prop.id, active: true).first

        if existing
          # Don't clobber a match staff have already started working.
          next unless existing.status == Match::STATUSES.first
          existing.update(score: score, score_band: Match.band_for(score, band_thresholds), explanation: explain(req, prop))
        elsif score >= min_score
          Match.create(
            requirement_id: req.id, property_id: prop.id,
            score: score, score_band: Match.band_for(score, band_thresholds), explanation: explain(req, prop),
            status: Match::STATUSES.first, assigned_user_id: req.customer&.assigned_user_id
          )
        end
        scored += 1
      end
    end
    scored
  end

  # Each *_score helper already returns its contribution pre-scaled to that
  # criterion's weight (e.g. location_score maxes out at weights[:location]),
  # so the total is a plain sum, capped at 100 by construction.
  def compute_score(req, prop)
    total = location_score(req, prop) + budget_score(req, prop) + type_score(req, prop) +
            size_score(req, prop) + intent_score(req, prop) + urgency_score(req, prop) +
            special_score(req, prop)
    total.round
  end

  def location_score(req, prop)
    locs = Array(req.locations)
    return weights[:location] if locs.empty?
    match = locs.any? { |l| prop.location.to_s.downcase.include?(l.to_s.downcase) }
    match ? weights[:location] : 0
  end

  def budget_score(req, prop)
    full = weights[:budget]
    return full if req.budget_min.nil? && req.budget_max.nil?
    return 0 if prop.price.nil?
    min = req.budget_min || 0
    max = req.budget_max
    return full if max.nil? ? prop.price >= min : prop.price.between?(min, max)
    tolerance = (max - min) * 0.1
    return full * 0.6 if prop.price.between?(min - tolerance, max + tolerance)
    0
  end

  def type_score(req, prop)
    types = Array(req.property_types)
    return weights[:property_type] if types.empty? || types.include?(prop.property_type)
    0
  end

  def size_score(req, prop)
    full = weights[:size]
    bedroom_match = req.bedrooms.present? && prop.bedrooms.present? && req.bedrooms == prop.bedrooms
    area_match = req.size_min.present? && req.size_max.present? && prop.area.present? &&
                 prop.area.between?(req.size_min, req.size_max)
    return full if bedroom_match || area_match
    return full * 0.5 if req.bedrooms.blank? && req.size_min.blank?
    0
  end

  def intent_score(req, prop)
    full = weights[:intent]
    return full if req.transaction_type == prop.transaction_type
    return full if req.transaction_type == 'invest' && prop.transaction_type == 'buy'
    0
  end

  def urgency_score(req, prop)
    full = weights[:urgency]
    return full if prop.status == 'available' && req.urgency == 'high'
    return full * 0.6 if prop.status == 'available'
    0
  end

  def special_score(req, prop)
    full = weights[:special]
    wanted = Array(req.amenities)
    return full if wanted.empty?
    have = Array(prop.amenities)
    overlap = (wanted & have).size
    (full * overlap / wanted.size.to_f)
  end

  def explain(req, prop)
    reasons = []
    reasons << "location matches #{Array(req.locations).join('/')}" if location_score(req, prop) >= weights[:location]
    reasons << 'within budget' if budget_score(req, prop) >= weights[:budget]
    reasons << "#{prop.property_type} matches preference" if type_score(req, prop) >= weights[:property_type]
    reasons << 'size/bedrooms fit' if size_score(req, prop) >= weights[:size] * 0.5
    reasons << 'transaction intent matches' if intent_score(req, prop) >= weights[:intent]
    reasons << 'ready availability' if urgency_score(req, prop) > 0
    reasons << 'shares preferred amenities' if special_score(req, prop) > 0
    reasons.empty? ? 'Limited overlap with stated preferences.' : reasons.map(&:capitalize).join('; ') + '.'
  end
end
