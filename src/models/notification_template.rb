class App::Models::NotificationTemplate < Sequel::Model
  CHANNELS = %w[in_app email sms whatsapp].freeze

  def validate
    super
    validates_presence [:name, :channel, :body]
    validates_includes CHANNELS, :channel, message: 'is not a valid channel'
    validates_unique(:name)
  end

  def variable_names
    JSON.parse(variables.to_s) rescue []
  end

  # Substitute {{placeholder}} tokens. Unknown/missing vars render as '' so a
  # template never leaks raw {{...}} markers to a recipient.
  def render(vars = {})
    lookup = vars.transform_keys(&:to_s)
    sub = ->(text) { text.to_s.gsub(/\{\{\s*(\w+)\s*\}\}/) { lookup[Regexp.last_match(1)].to_s } }
    { subject: sub.call(subject), body: sub.call(body) }
  end

  def to_pos
    as_json.merge('variable_names' => variable_names)
  end
end
