class App::Services::NotificationLogs < App::Services::Base
  def model; NotificationLog; end

  # Every user only ever sees their own notifications.
  def item(id=rp[:id])
    @item ||= begin
      record = model[id] || return_errors!("No notification found with id: #{id}", 404)
      unless record.recipient == current_user_obj&.id
        return_errors!('You do not have access to this notification.', 403)
      end
      record
    end
  end

  def list
    ds = model.where(active: true, recipient: current_user_obj.id)
    ds = ds.where(read: false) if qs[:unread].to_s == 'true'
    paginate(ds.order(Sequel.desc(:created_at)))
  end

  def create
    data = data_for(:save)
    # DB column defaults (channel/priority) aren't applied to a new in-memory
    # instance before validation runs — default them explicitly. New
    # notifications always start unread.
    data['channel']  ||= 'in_app'
    data['priority'] ||= 'medium'
    data['read'] = false
    save(model.new(data))
  end

  def mark_read
    item.update(read: true)
    return_success(item.to_pos)
  end

  def mark_all_read
    model.where(active: true, recipient: current_user_obj.id).update(read: true)
    return_success('All notifications marked as read.')
  end

  # ── Notification Center (super admin, route-gated) ──

  # GET /alerts/outbox — delivery monitor across ALL recipients/channels.
  def outbox
    ds = model.where(active: true)
    ds = ds.where(delivery_status: qs[:delivery_status]) if qs[:delivery_status].present?
    ds = ds.where(channel: qs[:channel])                 if qs[:channel].present?
    paginate(ds.order(Sequel.desc(:created_at)))
  end

  # POST /alerts/:id/retry — re-attempt a failed/pending delivery. Bypasses
  # the recipient-only `item` lookup on purpose (this is an admin action).
  def retry_delivery
    record = model[rp[:id]] || return_errors!("No notification found with id: #{rp[:id]}", 404)
    return_errors!('This notification was already delivered.', 400) if record.delivery_status == 'sent'
    App::Services::Notifier.attempt_delivery!(record)
    return_success(record.to_pos)
  end

  def self.fields
    { save: [:linked_type, :linked_id, :channel, :recipient, :title, :message, :priority] }
  end
end
