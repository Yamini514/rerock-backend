
class App::Routes < Roda
  include App::Router::AllPlugins
  plugin :not_found do
    { status: 'error', data: 'Not Found' }
  end

  def do_crud(klass, r, only='CRUDL', opts = {})
    r.post { klass[r, opts].create } if only.include?('C')
    r.get(Integer) {|id| klass[r, opts.merge(id: id)].get} if only.include?('R')
    r.get { klass[r, opts].list } if only.include?('L')
    r.put(Integer) {|id| klass[r, opts.merge(id: id)].update } if only.include?('U')
    r.delete(Integer) {|id| klass[r, opts.merge(id: id)].delete } if only.include?('D')
  end

  route do |r|
    r.public

    r.root do
      File.read(File.join(App.root, 'public', 'index.html'))
    end

    r.on 'admin' do
      r.get do
        File.read(File.join(App.root, 'public', 'index.html'))
      end
    end

    r.on 'api' do
      r.response['Content-Type'] = 'application/json'

      # ── Public endpoints (no auth required) ──
      r.post('login')                  { Session[r].login }
      r.post('register')               { Users[r].register }
      r.post('forgot-password')        { Users[r].forgot_password }
      r.post('validate-password-token'){ Users[r].validate_password_token }
      r.post('reset-password')         { Users[r].reset_password }

      r.get('version') { { status: 'success', version: 1 } }

      # ── Public property catalogue + lead capture (no auth) ──
      r.on 'public' do
        r.on('properties', Integer) {|id| Public[r, id: id].property }
        r.is('properties')          { Public[r].properties }
        r.get('stats')              { Public[r].stats }
        r.get('settings')           { Public[r].settings }
        r.post('enquiries')         { Public[r].enquire }
      end

      # ── Authentication required for everything below ──
      auth_required!
      # Read-only Viewer: server-side write block (frontend hiding alone is
      # never trusted). GETs pass; a small self-service allowlist stays open.
      viewer_write_guard!

      r.on 'me' do
        r.get('info')            { Users[r].info }
        r.put('profile')         { Users[r].update_profile }
        r.put('update-password') { Users[r].update_password }
        # A member-role user's own referral history (not the general staff endpoint).
        r.get('referrals')       { Referrals[r].mine }
        # The portal user's shortlist, stored on their linked Customer profile.
        r.on 'saved' do
          r.put(Integer) {|pid| Customers[r, property_id: pid].toggle_saved }
          r.get          { Customers[r].my_saved }
        end
        # The portal user's own enquiry/requirement history.
        r.get('enquiries') { Customers[r].my_enquiries }
      end

      begin
        # Customers + their requirements (staff read; writes are the Sales
        # Manager's / Business Owner's domain — SRS role matrix)
        r.on 'customers' do
          staff_required!
          r.on Integer do |cid|
            r.is('requirements') do
              r.get  { Requirements[r, customer_id: cid].list_for_customer }
              r.post { sales_write_required!; Requirements[r, customer_id: cid].create }
            end
            r.get    { Customers[r, id: cid].get }
            r.put    { sales_write_required!; Customers[r, id: cid].update }
            r.delete { sales_write_required!; Customers[r, id: cid].remove }
          end
          r.get  { Customers[r].list }
          r.post { sales_write_required!; Customers[r].create }
        end

        r.on 'requirements' do
          staff_required!
          sales_write_required!
          r.put(Integer)    {|id| Requirements[r, id: id].update }
          r.delete(Integer) {|id| Requirements[r, id: id].remove }
        end

        # Properties (staff read; writes: Property Manager, Sales Manager, admin+)
        r.on 'properties' do
          staff_required!
          do_crud(Properties, r, 'RL')
          r.post          { property_write_required!; Properties[r].create }
          r.put(Integer)  {|id| property_write_required!; Properties[r, id: id].update }
          # Deactivate rather than hard-delete (records should stay auditable).
          r.delete(Integer) { |id| property_write_required!; Properties[r, id: id].remove }
        end

        # Generic file upload -> S3 (writing roles only). Returns public URLs.
        r.on 'uploads' do
          staff_required!
          r.post { property_write_required!; Uploads[r].create }
        end

        # Members + Referrals (staff read; writes: Referral Coordinator, admin+)
        r.on 'members' do
          staff_required!
          r.post('recalculate-tiers') { super_admin_required!; Members[r].recalculate_tiers }
          do_crud(Members, r, 'RL')
          r.post            { referral_write_required!; Members[r].create }
          r.put(Integer)    {|id| referral_write_required!; Members[r, id: id].update }
          r.delete(Integer) { |id| referral_write_required!; Members[r, id: id].remove }
        end

        r.on 'referrals' do
          staff_required!
          do_crud(Referrals, r, 'RL')
          r.post            { referral_write_required!; Referrals[r].create }
          r.put(Integer)    {|id| referral_write_required!; Referrals[r, id: id].update }
          r.delete(Integer) { |id| referral_write_required!; Referrals[r, id: id].remove }
        end

        # Matches — the matching engine (staff read; writes: Sales Manager, admin+)
        r.on 'matches' do
          staff_required!
          r.post('recalculate') { sales_write_required!; Matches[r].recalculate }
          # Bulk status changes are an admin action (not per-agent).
          r.put('bulk') { admin_required!; Matches[r].bulk_update }
          do_crud(Matches, r, 'RL')
          r.post            { sales_write_required!; Matches[r].create }
          r.put(Integer)    {|id| sales_write_required!; Matches[r, id: id].update }
          r.delete(Integer) { |id| sales_write_required!; Matches[r, id: id].remove }
        end

        # Lightweight staff roster for assignment dropdowns — /users itself is
        # super-admin-only, so admins/agents need this narrower read.
        r.get('agents') { staff_required!; Users[r].agents }

        # Data import/export (CSV + XLSX). Export is role-gated per entity in
        # the service (agents scoped, viewer denied). Property import extends
        # to the Property Manager / Business Owner (SRS Property Intake
        # Workflow: "creates property record or imports property details");
        # all other imports remain super admin only.
        r.get('export', String)  { |entity| staff_required!; DataTransfer[r, entity: entity].export }
        r.post('import', String) { |entity| import_allowed!(entity); DataTransfer[r, entity: entity].import }

        # Follow-ups (staff only)
        r.on 'follow-ups' do
          staff_required!
          r.on Integer do |id|
            r.is('complete') { r.put { FollowUps[r, id: id].complete } }
            r.get    { FollowUps[r, id: id].get }
            r.put    { FollowUps[r, id: id].update }
            r.delete { FollowUps[r, id: id].remove }
          end
          r.post { FollowUps[r].create }
          r.get  { FollowUps[r].list }
        end

        # Alerts / in-app notifications — available to every authenticated
        # user (client/member included); each user only ever sees their own,
        # enforced inside NotificationLogsService by the recipient check.
        r.on 'alerts' do
          # Delivery monitor + retry (Notification Center, super admin only).
          r.get('outbox') { super_admin_required!; NotificationLogs[r].outbox }
          r.put('mark-all-read') { NotificationLogs[r].mark_all_read }
          r.on Integer do |id|
            r.post('retry') { super_admin_required!; NotificationLogs[r, id: id].retry_delivery }
            r.get    { NotificationLogs[r, id: id].get }
            r.put    { NotificationLogs[r, id: id].mark_read }
            r.delete { NotificationLogs[r, id: id].remove }
          end
          # Creating a notification for an arbitrary recipient is an admin
          # action — operational roles receive alerts, they don't mint them.
          r.post { admin_required!; NotificationLogs[r].create }
          r.get  { NotificationLogs[r].list }
        end

        # Notification templates (read: staff; write: super admin)
        r.on 'notification-templates' do
          staff_required!
          r.get { NotificationTemplates[r].list }
          super_admin_required!
          r.post { NotificationTemplates[r].create }
          r.on Integer do |id|
            r.put    { NotificationTemplates[r, id: id].update }
            r.delete { NotificationTemplates[r, id: id].remove }
          end
        end

        # Dashboards (staff only) — one endpoint per spec's six dashboards.
        # Agent numbers are scoped to their own records inside the service;
        # the referral dashboard (company earnings) is outside an agent's SRS
        # scope entirely, so it is denied at the route.
        r.on 'dashboard' do
          staff_required!
          r.get('overview')   { Dashboard[r].overview }
          r.get('properties') { Dashboard[r].properties }
          r.get('customers')  { Dashboard[r].customers }
          r.get('referrals')  { deny_agent!; Dashboard[r].referrals }
          r.get('matches')    { Dashboard[r].matches }
          r.get('follow-ups') { Dashboard[r].follow_ups }
        end

        # Master data (read: staff — forms need option lists; write: super admin)
        r.on 'master-data' do
          staff_required!
          r.get { MasterData[r].list }
          super_admin_required!
          r.post { MasterData[r].create }
          r.on Integer do |id|
            r.put('restore') { MasterData[r, id: id].restore }
            r.put    { MasterData[r, id: id].update }
            r.delete { MasterData[r, id: id].remove }
          end
        end

        # Application settings (read: staff). Writes: super admin for
        # everything; the Business Owner (admin) may update the whitelisted
        # business keys (matching weights, elite tiers) — SRS: "limited
        # technical settings". Key-level whitelist enforced in the service.
        r.on 'settings' do
          staff_required!
          r.put { admin_required!; Settings[r].bulk_update }
          r.get { Settings[r].list }
        end

        # User management (super admin only)
        r.on 'users' do
          super_admin_required!
          do_crud(Users, r, 'CRUL')
          # Deactivate rather than hard-delete (records should stay auditable).
          r.delete(Integer) { |id| Users[r, id: id].remove }
        end

        # Audit trail — read-only, append-only. The global log stays super
        # admin only; a per-record history is readable by staff (SRS
        # Auditability: "Users can see recent activity history on records"),
        # with agent ownership checked in the service.
        r.on 'activity-logs' do
          r.get('for', String, Integer) do |etype, eid|
            staff_required!
            ActivityLogs[r, entity_type: etype, entity_id: eid].for_entity
          end
          super_admin_required!
          r.get { ActivityLogs[r].list }
        end
      rescue => e
        App.logger.error("API Error: #{e.message}")
        App.logger.error(e.backtrace)
        { status: 'error', data: "An error occurred: #{e.message}" }
      end
    end

    # Fallback route
    r.get do
      File.read(File.join(App.root, 'public', 'index.html'))
    end
  end

  before do
    @time = Time.now
    App::Helpers::Before.run!(request)
  end

  after do |res|
    rtype = request.request_method
    App.logger.info("→ [#{Time.now - @time} seconds] - [#{rtype}]#{request.path}")
  end

  def auth_required!
    unless App.cu.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  end

  def staff_required!
    unless App.cu.user_obj.staff?
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'Forbidden!' }.to_json)
    end
  end

  def admin_required!
    unless (App.cu.user_obj.admin? || App.cu.user_obj.super_admin? || App.cu.user_obj.rgm?)
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'Forbidden!' }.to_json)
    end
  end

  def super_admin_required!
    unless App.cu.user_obj.super_admin?
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'Forbidden!' }.to_json)
    end
  end

  # ── SRS role-matrix guards (WI-2 / WI-3) ──────────────────────────────────
  # super_admin always passes; other roles must be explicitly listed.

  def forbid!(message = 'Forbidden!')
    request.halt(403, {'Content-Type' => 'application/json'},{ status: message }.to_json)
  end

  def roles_required!(*roles)
    u = App.cu.user_obj
    forbid! unless u && (u.super_admin? || roles.include?(u.role))
  end

  # Sales / Relationship Manager scope: customers, requirements, matches.
  def sales_write_required!
    roles_required!('admin', 'agent')
  end

  # Property Manager scope: properties + media uploads (agents keep their
  # existing scoped property writes; admin = Business Owner).
  def property_write_required!
    roles_required!('admin', 'agent', 'property_manager')
  end

  # Referral Coordinator scope: members + referrals.
  def referral_write_required!
    roles_required!('admin', 'referral_coordinator')
  end

  # Read-only Viewer: block every non-GET request except a small self-service
  # allowlist (own profile, own password, marking own alerts read).
  VIEWER_PUT_ALLOWLIST = %r{\A/api/(me/profile|me/update-password|alerts/mark-all-read|alerts/\d+)\z}.freeze
  def viewer_write_guard!
    u = App.cu.user_obj
    return unless u&.viewer?
    return if request.get?
    return if request.put? && request.path.match?(VIEWER_PUT_ALLOWLIST)
    forbid!('Forbidden! This account is read-only.')
  end

  # The referral dashboard exposes company-wide earnings — outside the Sales
  # Manager's SRS scope ("assigned and shared records").
  def deny_agent!
    forbid! if App.cu.user_obj.agent?
  end

  # Property import: Property Manager / Business Owner / Super Admin.
  # Every other entity's import stays super admin only.
  def import_allowed!(entity)
    u = App.cu.user_obj
    return if u.super_admin?
    return if entity == 'properties' && (u.admin? || u.property_manager?)
    forbid!
  end
end

App.require_blob('services/base.rb')
App.require_blob('services/*.rb')

App::Routes.send(:include, App::Services)