Sequel.migration do
  change do
    create_table(:follow_ups) do
      primary_key :id

      # Customer | Property | Referral | Match
      String :linked_type, size: 30, null: false
      Integer :linked_id, null: false

      DateTime :due_date, null: false

      # high | medium | low
      String :priority, size: 20, null: false, default: 'medium'

      Integer :owner_id, null: false

      # pending | completed
      String :status, size: 20, null: false, default: 'pending'

      String :notes, text: true
      DateTime :completed_at

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index [:linked_type, :linked_id]
      index :owner_id
      index :due_date
      index :status
      index :active
    end

    create_table(:notification_logs) do
      primary_key :id

      String :linked_type, size: 30
      Integer :linked_id

      String :channel, size: 20, null: false, default: 'in_app'
      Integer :recipient, null: false # user id

      String :title, null: false
      String :message, text: true

      TrueClass :read, null: false, default: false

      # high | medium | low
      String :priority, size: 20, null: false, default: 'medium'

      TrueClass :active, default: true

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index [:linked_type, :linked_id]
      index :recipient
      index :read
      index :active
    end
  end
end
