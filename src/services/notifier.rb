# Central notification dispatch — NOT a routed service. Other services call
#   Notifier.dispatch(recipient_id:, channel:, title:/message: or template:)
# which creates a NotificationLog row and attempts delivery for its channel:
#   in_app         -> delivered by existing (the /alerts feed reads the row)
#   email          -> real SMTP send via SmtpMail when configured
#   sms / whatsapp -> provider-ready stubs (row stays 'pending' until a
#                     provider is connected)
# Failures never propagate — a notification must never break the action that
# triggered it. Failed/pending rows can be retried from the Notification
# Center (POST /alerts/:id/retry).
module App::Services::Notifier
  module_function

  def dispatch(recipient_id:, channel: 'in_app', title: nil, message: nil,
               template: nil, vars: {}, linked_type: nil, linked_id: nil,
               priority: 'medium', to_email: nil)
    tpl = template.is_a?(String) ? App::Models::NotificationTemplate.where(name: template, active: true).first : template
    if tpl
      rendered = tpl.render(vars)
      title   ||= rendered[:subject]
      message ||= rendered[:body]
      channel   = tpl.channel
    end

    log = App::Models::NotificationLog.new(
      recipient: recipient_id, title: title.to_s, message: message,
      channel: channel, priority: priority, read: false,
      linked_type: linked_type, linked_id: linked_id,
      delivery_status: 'pending', attempts: 0, template_id: tpl&.id
    )
    unless log.save
      App.logger.error("Notifier: could not create notification log: #{log.errors.inspect}")
      return nil
    end

    attempt_delivery!(log, to_email: to_email)
  rescue => e
    App.logger.error("Notifier.dispatch failed: #{e.message}")
    nil
  end

  # Also used by the retry endpoint; updates delivery bookkeeping in place.
  def attempt_delivery!(log, to_email: nil)
    log.attempts = (log.attempts || 0) + 1
    log.last_attempted_at = Time.now

    case log.channel
    when 'email'
      email = to_email || App::Models::User[log.recipient]&.email
      if email.to_s.strip.empty?
        log.delivery_status, log.last_error = 'failed', 'Recipient has no email address.'
      elsif !SmtpMail.configured?
        log.delivery_status, log.last_error = 'failed', 'SMTP not configured (set SMTP_HOST in .env).'
      else
        begin
          SmtpMail.send_mail(to: email, subject: log.title, body: log.message.to_s)
          log.delivery_status, log.last_error = 'sent', nil
        rescue => e
          log.delivery_status, log.last_error = 'failed', e.message
        end
      end
    when 'sms', 'whatsapp'
      # Channel is modeled and queued; stays pending until a provider is wired.
      log.delivery_status = 'pending'
      log.last_error = "#{log.channel} provider not connected."
    else # in_app
      log.delivery_status, log.last_error = 'sent', nil
    end

    log.save
    log
  end
end
