class App::Services::Requirements < App::Services::Base
  def model; Requirement; end

  # Requirement itself has no assigned_user_id — ownership follows the parent customer.
  def item(id=rp[:id])
    @item ||= begin
      record = model[id] || return_errors!("No #{model.class} found with id: #{id}", 404)
      assert_owns!(record.customer)
      record
    end
  end

  # GET /customers/:id/requirements
  def list_for_customer
    cid = rp[:customer_id]
    customer = Customer[cid] || return_errors!("No customer found with id: #{cid}", 404)
    assert_owns!(customer)
    return_success(
      model.where(customer_id: cid, active: true)
           .order(Sequel.desc(:created_at)).all.map(&:to_pos)
    )
  end

  # POST /customers/:id/requirements
  def create
    cid = rp[:customer_id]
    customer = Customer[cid] || return_errors!("No customer found with id: #{cid}", 404)
    assert_owns!(customer)
    data = data_for(:save)
    obj  = model.new(data)
    obj.customer_id = cid
    save(obj) do |req|
      App::Services::Matches[r].rescore_requirement!(req)
      return_success(req.to_pos)
    end
  end

  def update
    data = data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |req|
      App::Services::Matches[r].rescore_requirement!(req)
      return_success(req.to_pos)
    end
  end

  def self.fields
    {
      save: [
        :customer_id, :transaction_type, :property_types, :locations, :amenities,
        :budget_min, :budget_max, :size_min, :size_max, :bedrooms, :urgency,
        :special_requirements, :notes, :status
      ]
    }
  end
end
