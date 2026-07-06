Sequel.migration do
  change do
    create_table(:members) do
      primary_key :id

      String :name, null: false
      String :email, size: 150
      String :phone, size: 20, null: false

      # buyer | seller | investor | source
      String :member_type, size: 30, null: false, default: 'source'

      # active | inactive
      String :status, size: 30, null: false, default: 'active'

      String :relationship_notes, text: true

      # Standard | Silver | Gold | Elite — computed on save, not user-set.
      String :tier, size: 20, null: false, default: 'Standard'

      String :referral_code, size: 40, null: false

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :referral_code, unique: true
      index :member_type
      index :status
      index :active
    end

    create_table(:referrals) do
      primary_key :id

      foreign_key :member_id, :members, null: false, on_delete: :cascade

      # buyer | seller | investor | property
      String :referral_type, size: 30, null: false, default: 'buyer'

      Integer :linked_customer_id
      Integer :linked_property_id

      Integer :expected_value
      Integer :closure_value

      # New | Reviewed | Contacted | Qualified | In Progress | Converted | Rejected | Duplicate
      String :status, size: 30, null: false, default: 'New'

      String :notes, text: true
      Date :date

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :member_id
      index :status
      index :linked_customer_id
      index :linked_property_id
      index :active
    end
  end
end
