Sequel.migration do
  change do
    create_table(:notification_templates) do
      primary_key :id

      String :name, size: 120, null: false

      # in_app | email | sms | whatsapp
      String :channel, size: 20, null: false, default: 'in_app'

      # Subject line (email) / title (in-app).
      String :subject, size: 200

      # Body with {{placeholder}} variables.
      String :body, text: true, null: false

      # JSON array of allowed placeholder names, e.g. ["name","property_title"].
      String :variables, text: true

      String :description, text: true

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :name, unique: true
      index :channel
      index :active
    end
  end
end
