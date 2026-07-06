Sequel.migration do
  change do
    create_table(:requirements) do
      primary_key :id

      foreign_key :customer_id, :customers, null: false, on_delete: :cascade

      # buy | rent | invest
      String :transaction_type, size: 20, null: false, default: 'buy'

      column :property_types, 'text[]', default: '{}'
      column :locations, 'text[]', default: '{}'
      column :amenities, 'text[]', default: '{}'

      Integer :budget_min
      Integer :budget_max
      Integer :size_min
      Integer :size_max
      Integer :bedrooms

      # low | medium | high
      String :urgency, size: 20, default: 'medium'

      String :special_requirements, text: true
      String :notes, text: true

      # open | matched | closed
      String :status, size: 20, null: false, default: 'open'

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :customer_id
      index :status
      index :active
    end
  end
end
