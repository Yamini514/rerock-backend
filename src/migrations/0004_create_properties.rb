Sequel.migration do
  change do
    create_table(:properties) do
      primary_key :id

      String :code, size: 30, null: false
      String :title, null: false

      # Apartment | Villa | Studio | Penthouse | Commercial | Plot
      String :property_type, size: 40, null: false

      # buy | rent
      String :transaction_type, size: 20, null: false, default: 'buy'

      String :location, null: false
      String :city, size: 120

      Integer :price            # in rupees
      Integer :area             # in sqft
      Integer :bedrooms
      Integer :bathrooms

      # draft | available | under_discussion | blocked | sold | inactive
      String :status, size: 30, null: false, default: 'draft'

      # Optional attributes
      String :facing, size: 40
      String :floor, size: 40
      String :age, size: 40
      String :furnishing, size: 40
      String :parking, size: 40
      String :possession_status, size: 60
      column :amenities, 'text[]', default: '{}'
      column :approvals, 'text[]', default: '{}'
      column :tags, 'text[]', default: '{}'

      # Owner / source (confidential)
      String :owner_name, size: 150
      String :owner_contact, size: 60
      Integer :source_member_id
      String :source_notes, text: true
      TrueClass :confidential, default: false

      # Media (links in Phase 1)
      String :image, text: true
      column :images, 'text[]', default: '{}'
      String :map_link, text: true
      String :brochure_link, text: true

      String :notes, text: true   # internal, not public-facing

      Integer :assigned_user_id   # agent
      Date :listed_date

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :code, unique: true
      index :property_type
      index :status
      index :location
      index :assigned_user_id
      index :active
    end
  end
end
