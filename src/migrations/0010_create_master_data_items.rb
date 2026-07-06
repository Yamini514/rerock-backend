Sequel.migration do
  change do
    create_table(:master_data_items) do
      primary_key :id

      # property_types | locations | lead_sources | referral_sources |
      # member_types | property_statuses | customer_statuses |
      # followup_statuses | tags
      String :category, size: 60, null: false

      # Canonical stored value (what other tables persist), e.g. 'visit_planned'
      String :value, size: 120, null: false

      # Display label, e.g. 'Visit Planned'
      String :label, size: 150, null: false

      Integer :sort_order, default: 0

      # System rows are referenced by code logic (e.g. property 'sold',
      # requirement 'open') — their value can't be edited, only deactivated.
      TrueClass :is_system, default: false

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :category
      index :active
      index [:category, :value], unique: true
    end
  end
end
