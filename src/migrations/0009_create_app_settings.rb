Sequel.migration do
  change do
    create_table(:app_settings) do
      primary_key :id

      # Namespaced key, e.g. company.name | branding.logo_url | locale.timezone |
      # matching.weights | elite_tiers.rules | security.password_min_length
      String :setting_key, size: 120, null: false

      # Stored as text; structured values (weights, tier rules) are JSON-encoded
      # and declared as value_type 'json'.
      String :value, text: true

      # string | number | boolean | json
      String :value_type, size: 20, null: false, default: 'string'

      # UI grouping: company | branding | locale | email | business |
      # matching | elite_tiers | security
      String :group, size: 60, null: false, default: 'general'

      String :label, size: 150
      String :description, text: true

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :setting_key, unique: true
      index :group
      index :active
    end
  end
end
