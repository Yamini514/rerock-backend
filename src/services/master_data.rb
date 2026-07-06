class App::Services::MasterData < App::Services::Base
  def model; MasterDataItem; end

  # GET /master-data?category=...&include_inactive=1
  # Read is staff-wide (every form needs the option lists); writes are gated
  # to super_admin at the route layer.
  def list
    ds = model.dataset
    ds = ds.where(active: true) unless qs[:include_inactive].present?
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    paginate(ds.order(:category, :sort_order, :label))
  end

  def create
    data = data_for(:save)
    save(model.new(data)) { |item| flush_and_return(item) }
  end

  def update
    data = data_for(:save)
    item.set_fields(data, data.keys)
    save(item) { |i| flush_and_return(i) }
  end

  def remove
    item.active = false
    save(item) { |i| flush_and_return(i) }
  end

  # Reactivate a previously deactivated entry.
  def restore
    item.active = true
    save(item) { |i| flush_and_return(i) }
  end

  def self.fields
    {
      save: [:category, :value, :label, :sort_order]
    }
  end

  private

  # Values are cached per request thread; after a write the current request
  # must see fresh values (e.g. validation on a follow-up save later in tests).
  def flush_and_return(item)
    model.clear_cache!
    return_success(item.to_pos)
  end
end
