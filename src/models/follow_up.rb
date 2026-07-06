class App::Models::FollowUp < Sequel::Model
  LINKED_TYPES = %w[Customer Property Referral Match].freeze
  PRIORITIES   = %w[high medium low].freeze
  STATUSES     = %w[pending completed].freeze

  many_to_one :owner, class: 'App::Models::User', key: :owner_id

  def validate
    super
    validates_presence [:linked_type, :linked_id, :due_date, :owner_id, :status]
    validates_includes LINKED_TYPES, :linked_type, message: 'is not a valid linked type'
    validates_includes PRIORITIES, :priority, message: 'is not a valid priority' if priority
    # Status list is master-data driven (Super Admin configurable).
    validates_includes App::Models::MasterDataItem.values_for(:followup_statuses, fallback: STATUSES),
                       :status, message: 'is not a valid status'
  end

  def before_save
    self.completed_at = (status == 'completed' ? (completed_at || Time.now) : nil)
    super
  end

  def to_pos
    as_json.merge('linked_label' => linked_label, 'owner_name' => owner&.full_name)
  end

  private

  # linked_type/linked_id is a lightweight polymorphic reference — there's no
  # single association to eager-load, so this resolves per-row like
  # Match#to_pos/Referral#to_pos already do for their own associations.
  def linked_label
    case linked_type
    when 'Customer' then App::Models::Customer[linked_id]&.name
    when 'Property' then App::Models::Property[linked_id]&.title
    when 'Referral' then App::Models::Referral[linked_id]&.member&.name
    when 'Match'    then App::Models::Match[linked_id]&.property&.title
    end
  end
end
