require 'mail'

# SMTP delivery configured from the documented .env names (SMTP_HOST,
# SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM). Nothing happens at load
# time — `configured?` gates every send, so an unconfigured environment
# degrades gracefully (Notifier marks the delivery failed instead of raising
# at boot).
module SmtpMail
  def self.configured?
    ENV['SMTP_HOST'].to_s.strip != ''
  end

  def self.setup!
    return if @configured
    port = (ENV['SMTP_PORT'] || 587).to_i
    options = {
      address: ENV['SMTP_HOST'],
      port: port,
      user_name: ENV['SMTP_USER'],
      password: ENV['SMTP_PASSWORD'],
      authentication: 'plain',
      enable_starttls_auto: true,
    }
    options[:ssl] = true if port == 465
    Mail.defaults { delivery_method :smtp, options }
    @configured = true
  end

  # Raises on failure — the caller (Notifier) records the error on the log row.
  def self.send_mail(to:, subject:, body:)
    raise 'SMTP is not configured (SMTP_HOST is empty).' unless configured?
    setup!
    sender = ENV['SMTP_FROM'].to_s.strip.empty? ? ENV['SMTP_USER'] : ENV['SMTP_FROM']
    mail = Mail.new
    mail.from    = sender
    mail.to      = to
    mail.subject = subject
    mail.body    = body
    mail.deliver!
  end
end
