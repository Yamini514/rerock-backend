Sequel.migration do
  change do
    add_index :properties, :transaction_type
    add_index :members, :tier
    add_index :referrals, :referral_type
    add_index :matches, :property_id
  end
end
