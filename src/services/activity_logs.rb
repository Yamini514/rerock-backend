class App::Services::ActivityLogs < App::Services::Base
  def model; ActivityLog; end

  # GET /activity-logs — read-only, super admin gated at the route layer.
  # The log is append-only: there are deliberately no create/update/delete
  # routes for this service.
  def list
    ds = model.dataset
    ds = ds.where(action: qs[:action])           if qs[:action].present?
    ds = ds.where(entity_type: qs[:entity_type]) if qs[:entity_type].present?
    ds = ds.where(user_id: qs[:user_id])         if qs[:user_id].present?
    # Hoisted locals: zero-arity where{} blocks are instance_exec'd against
    # VirtualRow, where `qs` would not resolve to the service method.
    if qs[:from].present?
      from_time = Date.parse(qs[:from]).to_time
      ds = ds.where { created_at >= from_time }
    end
    if qs[:to].present?
      to_time = (Date.parse(qs[:to]) + 1).to_time
      ds = ds.where { created_at < to_time }
    end
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:user_email, q),
        Sequel.ilike(:details, q),
        Sequel.ilike(:entity_type, q)
      ))
    end
    paginate(ds.order(Sequel.desc(:created_at)).eager(:user))
  rescue Date::Error
    return_errors!('Invalid date filter (expected YYYY-MM-DD).', 400)
  end

  # GET /activity-logs/for/:entity_type/:id — the audit trail for ONE record
  # (SRS Auditability: "Users can see recent activity history on records").
  # Staff-readable, but the caller must be able to open the record itself:
  # the same ownership rule as the record's detail endpoint (agents are
  # restricted to assigned records / own follow-ups).
  HISTORY_ENTITIES = {
    'Customer' => -> { App::Models::Customer }, 'Property' => -> { App::Models::Property },
    'Member'   => -> { App::Models::Member },   'Referral' => -> { App::Models::Referral },
    'Match'    => -> { App::Models::Match },    'FollowUp' => -> { App::Models::FollowUp },
    'Requirement' => -> { App::Models::Requirement },
  }.freeze

  def for_entity
    etype = rp[:entity_type].to_s
    klass = HISTORY_ENTITIES[etype] || return_errors!("Unknown entity type: #{etype}", 404)
    record = klass.call[rp[:entity_id]] || return_errors!('Record not found', 404)

    # Ownership mirrors the detail endpoints: requirements follow their
    # customer, follow-ups their owner, the rest their assigned user.
    case record
    when App::Models::Requirement then assert_owns!(record.customer)
    when App::Models::FollowUp
      u = current_user_obj
      return_errors!('You do not have access to this record.', 403) if u&.agent? && record.owner_id != u.id
    else assert_owns!(record)
    end

    rows = model.where(entity_type: etype, entity_id: record.pk)
                .order(Sequel.desc(:created_at)).limit(50).eager(:user).all
    return_success(rows.map(&:to_pos))
  end
end
