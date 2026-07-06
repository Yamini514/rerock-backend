Sequel.migration do
  change do
    create_table(:matches) do
      primary_key :id

      foreign_key :requirement_id, :requirements, null: false, on_delete: :cascade
      foreign_key :property_id, :properties, null: false, on_delete: :cascade

      # Nullable — a manually-logged enquiry has no engine score, only an
      # engine-run match does. Same table serves both.
      Integer :score
      # High | Medium | Low | Not Recommended
      String :score_band, size: 30
      String :explanation, text: true

      # New | Contacted | Shortlisted | Rejected | Visit Planned | Negotiation | Closed
      String :status, size: 30, null: false, default: 'New'

      # high | medium | low
      String :priority, size: 20, null: false, default: 'medium'

      DateTime :next_followup_at
      String :notes, text: true

      Integer :assigned_user_id

      TrueClass :active, default: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index [:requirement_id, :property_id], unique: true
      index :status
      index :score_band
      index :assigned_user_id
      index :active
    end
  end
end
