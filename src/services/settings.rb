class App::Services::Settings < App::Services::Base
  def model; AppSetting; end

  # GET /settings — every active setting, ordered for the grouped admin UI.
  # Readable by all staff (forms need locale/currency); writes are gated to
  # super_admin at the route layer.
  def list
    rows = model.where(active: true).order(:group, :setting_key).all
    return_success(rows.map(&:to_pos))
  end

  # Business keys the Business Owner (admin) may update — SRS: "limited
  # technical settings". Everything else stays super admin only.
  ADMIN_WRITABLE_PREFIXES = %w[matching. elite_tiers.].freeze

  # PUT /settings — bulk update of KNOWN keys only ({ data: { settings: {key => value} } }).
  # New keys are never created from the API; the seeded catalogue is the schema.
  def bulk_update
    incoming = params[:settings]
    return_errors!('No settings provided', 400) unless incoming.is_a?(Hash) && !incoming.empty?

    keys = incoming.keys.map(&:to_s)

    # Route admits admin + super_admin; admin is limited to business keys.
    # Reject the whole payload on any out-of-scope key — never silently filter.
    unless current_user_obj&.super_admin?
      blocked = keys.reject { |k| ADMIN_WRITABLE_PREFIXES.any? { |p| k.start_with?(p) } }
      return_errors!("Not permitted to change: #{blocked.join(', ')}", 403) unless blocked.empty?
    end
    known = model.where(setting_key: keys).all.to_h { |s| [s.setting_key, s] }
    unknown = keys - known.keys
    return_errors!("Unknown setting(s): #{unknown.join(', ')}", 400) unless unknown.empty?

    changed = {}
    App.db.transaction do
      incoming.each do |key, value|
        row = known[key.to_s]
        encoded = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
        next if row.value == encoded
        changed[key.to_s] = [row.value, encoded]
        row.value = encoded
        return_errors!(row.errors, 400) unless row.save
      end
    end
    model.clear_cache!

    unless changed.empty?
      ActivityLog.record!(action: 'settings_changed', changes: changed,
                          details: "Updated #{changed.size} setting(s): #{changed.keys.join(', ')}")
    end
    list
  end
end
