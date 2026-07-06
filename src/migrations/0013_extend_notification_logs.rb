Sequel.migration do
  change do
    alter_table(:notification_logs) do
      # pending | sent | failed — existing rows were all delivered in-app,
      # so 'sent' is the correct backfill default.
      add_column :delivery_status, String, size: 20, null: false, default: 'sent'
      add_column :attempts, Integer, default: 0
      add_column :last_error, String, text: true
      add_column :last_attempted_at, DateTime
      add_column :template_id, Integer

      # Bring this table in line with every other table's audit columns
      # (it was the only one missing them).
      add_column :created_by, Integer
      add_column :updated_by, Integer

      add_index :delivery_status
    end
  end
end
