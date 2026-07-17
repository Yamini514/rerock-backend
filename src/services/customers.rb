class App::Services::Customers < App::Services::Base
  def model; Customer; end

  def list
    ds = model.where(active: true)
    ds = ds.where(lead_type: qs[:lead_type]) if qs[:lead_type].present?
    ds = ds.where(status: qs[:status])       if qs[:status].present?
    ds = ds.where(assigned_user_id: qs[:assigned_user_id]) if qs[:assigned_user_id].present?
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:name, q),
        Sequel.ilike(:phone, q),
        Sequel.ilike(:email, q)
      ))
    end
    paginate(scope_to_assigned(ds).order(Sequel.desc(:created_at)).eager(:requirements, :assigned_user))
  end

  def create
    save(model.new(guarded_data(new_record: true)))
  end

  def update
    data = guarded_data
    item.set_fields(data, data.keys)
    save(item)
  end

  # ── /me/saved — the logged-in portal user's shortlist ──
  # Backed by the saved_property_ids array on their linked Customer profile.
  # A Customer row is auto-created on first save so a self-registered client
  # (who has no staff-created profile yet) can still shortlist.

  def my_saved
    c = my_customer
    ids = (c&.saved_property_ids || []).to_a
    props = ids.empty? ? [] : Property.where(id: ids, active: true).all.map(&:to_pos)
    return_success(ids: ids, properties: props)
  end

  def toggle_saved
    pid = rp[:property_id].to_i
    return_errors!('Property not found', 404) unless Property.where(id: pid, active: true).first

    c = my_customer(create: true)
    ids = (c.saved_property_ids || []).to_a
    ids.include?(pid) ? ids.delete(pid) : ids.push(pid)
    c.saved_property_ids = Sequel.pg_array(ids, :integer)
    save(c) { return_success(ids: ids) }
  end

  # ── /me/enquiries — the logged-in portal user's own requirement history ──
  def my_enquiries
    c = my_customer
    reqs = c ? Requirement.where(customer_id: c.id, active: true)
                          .order(Sequel.desc(:created_at)).all.map(&:to_pos) : []
    return_success(reqs)
  end

  def self.fields
    {
      save: [
        :name, :email, :phone, :alt_phone, :lead_type, :city, :source,
        :preferred_language, :status, :assigned_user_id, :saved_property_ids,
        :shared, :notes, :next_followup_at, :last_followup_at
      ]
    }
  end

  private

  def my_customer(create: false)
    u = current_user_obj
    c = u.customer_id && Customer.where(id: u.customer_id, active: true).first
    return c if c || !create

    c = Customer.new(
      name: u.full_name, phone: u.phone_number.presence || 'Not provided',
      email: u.email, lead_type: 'buyer', status: 'new', source: 'portal'
    )
    return_errors!(c.errors, 400) unless c.save
    u.update(customer_id: c.id)
    c
  end

  # Agents can't reassign ownership or move records in/out of the shared
  # pool; their new leads auto-assign to themselves.
  def guarded_data(new_record: false)
    data = data_for(:save)
    u = current_user_obj
    if u&.agent?
      data.delete('assigned_user_id')
      data.delete('shared')
      data['assigned_user_id'] = u.id if new_record
    end
    data
  end
end
