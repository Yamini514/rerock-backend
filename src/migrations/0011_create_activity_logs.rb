Sequel.migration do
  change do
    # Append-only audit trail — no active/updated_* columns on purpose:
    # rows are never edited or soft-deleted.
    create_table(:activity_logs) do
      primary_key :id

      Integer :user_id
      # Denormalized so the log entry survives later user email changes.
      String :user_email, size: 150

      # create | update | deactivate | login | login_failed | logout |
      # password_reset_requested | password_reset_completed | role_changed |
      # import | export | settings_changed
      String :action, size: 40, null: false

      String :entity_type, size: 60
      Integer :entity_id

      # JSON of changed columns {col => [old, new]}, sensitive fields stripped.
      String :changes, text: true

      String :ip, size: 64
      String :details, text: true

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
      index :action
      index :entity_type
      index [:entity_type, :entity_id]
      index :created_at
    end
  end
end
