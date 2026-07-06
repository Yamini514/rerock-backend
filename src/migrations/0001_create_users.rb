Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id

      String :full_name, null: false
      String :email, size: 150, null: false
      String :encoded_password, size: 200
      String :phone_number, size: 20

      # admin | agent | client | member
      String :role, size: 30, null: false, default: 'agent'

      # Portal users (client/member) may link to a CRM record.
      Integer :customer_id
      Integer :member_id

      # Password reset
      String :reset_token, size: 100
      DateTime :reset_sent_at

      # Single active session token (matches CurrentUser.valid?)
      String :current_session_id, text: true
      DateTime :last_logged_in_at

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :email, unique: true
      index :role
      index :active
    end
  end
end
