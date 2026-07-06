Sequel.migration do
  change do
    create_table(:customers) do
      primary_key :id

      String :name, null: false
      String :email, size: 150
      String :phone, size: 20, null: false
      String :alt_phone, size: 20

      # buyer | seller | investor | tenant | owner | enquiry
      String :lead_type, size: 30, null: false, default: 'buyer'

      String :city, size: 120
      String :source, size: 120
      String :preferred_language, size: 60

      # new | contacted | qualified | shortlisted | visit_planned |
      # negotiation | closed | lost | on_hold
      String :status, size: 30, null: false, default: 'new'

      Integer :assigned_user_id

      column :saved_property_ids, 'integer[]', default: '{}'

      String :notes, text: true

      DateTime :last_followup_at
      DateTime :next_followup_at

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :lead_type
      index :status
      index :assigned_user_id
      index :active
    end
  end
end
