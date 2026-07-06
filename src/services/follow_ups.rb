class App::Services::FollowUps < App::Services::Base
  def model; FollowUp; end

  # Operational roles own their tasks: agents, property managers, and
  # referral coordinators each see and manage only their own follow-ups.
  # Admin (Business Owner), Super Admin, and the read-only Viewer see all.
  OWNER_SCOPED_ROLES = %w[agent property_manager referral_coordinator].freeze

  def owner_scoped?
    u = current_user_obj
    u && OWNER_SCOPED_ROLES.include?(u.role)
  end

  # FollowUp uses `owner_id`, not `assigned_user_id` — Base's generic
  # assert_owns! doesn't cover it, so ownership is enforced here directly.
  def item(id=rp[:id])
    @item ||= begin
      record = model[id] || return_errors!("No follow-up found with id: #{id}", 404)
      if owner_scoped? && record.owner_id != current_user_obj.id
        return_errors!('You do not have access to this record.', 403)
      end
      record
    end
  end

  def list
    ds = model.where(active: true)
    ds = ds.where(status: qs[:status])         if qs[:status].present?
    ds = ds.where(linked_type: qs[:linked_type]) if qs[:linked_type].present?
    ds = ds.where(owner_id: qs[:owner_id])      if qs[:owner_id].present?
    ds = ds.where(owner_id: current_user_obj.id) if owner_scoped?
    paginate(ds.order(Sequel.asc(:due_date)).eager(:owner))
  end

  def create
    data = data_for(:save)
    u = current_user_obj
    # Operational roles can only own their own follow-ups — can't hand a
    # task to someone else.
    data['owner_id'] = u.id if owner_scoped?
    data['owner_id'] ||= u&.id
    # DB column defaults (status/priority) aren't applied to a new in-memory
    # instance before validation runs — default them explicitly.
    data['status']   ||= FollowUp::STATUSES.first
    data['priority'] ||= 'medium'
    save(model.new(data))
  end

  def update
    data = data_for(:save)
    data.delete('owner_id') if owner_scoped? # can't reassign to someone else
    item.set_fields(data, data.keys)
    save(item)
  end

  def complete
    item.update(status: 'completed')
    return_success(item.to_pos)
  end

  def self.fields
    {
      save: [
        :linked_type, :linked_id, :due_date, :priority,
        :owner_id, :status, :notes
      ]
    }
  end
end
