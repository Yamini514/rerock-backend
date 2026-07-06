module SequelPlugin
  # Automatic audit trail: writes an ActivityLog row after create/update on
  # the allowlisted domain models (and logs destroys, which only Members can
  # trigger today via the login-provision rollback). Registered globally in
  # App.setup_sequel! next to SaveUserId; non-audited models are untouched.
  module AuditLog
    AUDITED_MODELS = %w[
      User Customer Property Requirement Member Referral Match FollowUp
      AppSetting MasterDataItem NotificationTemplate
    ].freeze

    # Bookkeeping columns — a change touching only these isn't worth a log row.
    NOISE_COLUMNS = %w[updated_at updated_by created_at created_by last_logged_in_at current_session_id reset_token reset_sent_at].freeze

    module InstanceMethods
      def after_create
        super
        audit!('create', nil) if audited?
      end

      def after_update
        super
        return unless audited?
        changes = (previous_changes || {}).reject { |k, _| NOISE_COLUMNS.include?(k.to_s) }
        return if changes.empty?

        action = 'update'
        action = 'deactivate' if changes[:active] == [true, false]
        audit!(action, changes)

        # A role change on a user account is security-relevant — log it as its
        # own action on top of the generic update.
        if is_a?(App::Models::User) && changes[:role]
          audit!('role_changed', { role: changes[:role] })
        end
      end

      def after_destroy
        super
        audit!('deactivate', nil, details: 'Record hard-deleted') if audited?
      end

      private

      def audited?
        AUDITED_MODELS.include?(self.class.name.split('::').last)
      end

      def audit!(action, changes, details: nil)
        App::Models::ActivityLog.record!(action: action, entity: self, changes: changes, details: details)
      end
    end
  end
end
