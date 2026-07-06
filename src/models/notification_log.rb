class App::Models::NotificationLog < Sequel::Model
  PRIORITIES = %w[high medium low].freeze

  def validate
    super
    validates_presence [:recipient, :title]
    validates_includes PRIORITIES, :priority, message: 'is not a valid priority' if priority
  end

  def to_pos
    as_json
  end
end
