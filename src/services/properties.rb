class App::Services::Properties < App::Services::Base
  def model; Property; end

  def list
    paginate(scoped)
  end

  def create
    save(model.new(guarded_data(new_record: true))) do |prop|
      App::Services::Matches[r].rescore_property!(prop)
      return_success(prop.to_pos)
    end
  end

  def update
    data = guarded_data
    item.set_fields(data, data.keys)
    save(item) do |prop|
      App::Services::Matches[r].rescore_property!(prop)
      return_success(prop.to_pos)
    end
  end

  # Shared filterable, ordered dataset (used by admin list).
  def scoped(base = model.where(active: true))
    ds = base
    ds = ds.where(property_type: qs[:property_type])       if qs[:property_type].present?
    ds = ds.where(status: qs[:status])                     if qs[:status].present?
    ds = ds.where(transaction_type: qs[:transaction_type]) if qs[:transaction_type].present?
    ds = ds.where(assigned_user_id: qs[:assigned_user_id]) if qs[:assigned_user_id].present?
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:title, q),
        Sequel.ilike(:location, q),
        Sequel.ilike(:code, q)
      ))
    end
    scope_to_assigned(ds).order(Sequel.desc(:created_at)).eager(:assigned_user)
  end

  def self.fields
    {
      save: [
        :code, :title, :property_type, :transaction_type, :location, :city,
        :price, :area, :bedrooms, :bathrooms, :status, :facing, :floor, :age,
        :furnishing, :parking, :possession_status, :amenities, :approvals, :tags,
        :owner_name, :owner_contact, :source_member_id, :source_notes, :confidential,
        :shared, :image, :images, :map_link, :brochure_link, :notes, :assigned_user_id, :listed_date
      ]
    }
  end

  private

  # Only a Super Admin may mark a property confidential — strip the field
  # server-side so the UI toggle can't be bypassed with a raw API call.
  # Only admin+ may share a record into the team pool. Agents can't reassign
  # ownership; their new listings auto-assign to themselves.
  def guarded_data(new_record: false)
    data = data_for(:save)
    u = current_user_obj
    data.delete('confidential') unless u&.super_admin?
    data.delete('shared') unless u&.super_admin? || u&.admin?
    if u&.agent?
      data.delete('assigned_user_id')
      data['assigned_user_id'] = u.id if new_record
    end
    data
  end
end
