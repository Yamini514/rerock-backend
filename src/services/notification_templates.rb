class App::Services::NotificationTemplates < App::Services::Base
  def model; NotificationTemplate; end

  # Read is staff-wide; writes are super admin only (route layer).
  def list
    ds = model.where(active: true)
    ds = ds.where(channel: qs[:channel]) if qs[:channel].present?
    paginate(ds.order(:name))
  end

  def self.fields
    {
      save: [:name, :channel, :subject, :body, :variables, :description]
    }
  end
end
