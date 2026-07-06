Sequel.migration do
  change do
    # SRS User Roles: the Sales Manager has "operational access to assigned
    # AND SHARED records". `shared: true` places a record in the team pool —
    # visible and workable to every agent alongside their own assigned rows.
    # Only admin/super_admin may set the flag (enforced in the services).
    alter_table(:customers) do
      add_column :shared, TrueClass, default: false, null: false
      add_index :shared
    end

    alter_table(:properties) do
      add_column :shared, TrueClass, default: false, null: false
      add_index :shared
    end
  end
end
