# Unauthenticated public catalogue. Only exposes published (available),
# active properties. Confidential owner/source fields are stripped by
# Property#to_pos because there is no logged-in staff user.
class App::Services::Public < App::Services::Base

  # GET /api/public/properties
  def properties
    ds = Property.where(active: true, status: 'available')
    ds = ds.where(property_type: qs[:property_type])       if qs[:property_type].present?
    ds = ds.where(transaction_type: qs[:transaction_type]) if qs[:transaction_type].present?
    if qs[:search].present?
      q = "%#{qs[:search]}%"
      ds = ds.where(Sequel.|(
        Sequel.ilike(:title, q),
        Sequel.ilike(:location, q)
      ))
    end
    paginate(ds.order(Sequel.desc(:created_at)))
  end

  # GET /api/public/properties/:id
  def property
    p = Property[rp[:id]]
    if p && p.active && p.status == 'available'
      return_success(p.to_pos)
    else
      return_errors!('Property not found', 404)
    end
  end

  # GET /api/public/stats — real, live counts for the marketing site
  # (replaces hardcoded "10,000+ listings" style copy on the frontend).
  def stats
    listings = Property.where(active: true, status: 'available')
    return_success(
      listings: listings.count,
      cities:   listings.exclude(city: nil).exclude(city: '').select(:city).distinct.count,
      agents:   User.where(active: true, role: 'agent').count,
      happy_clients: Customer.where(active: true, status: 'closed').count
    )
  end

  # GET /api/public/settings — branding/company subset for the public site
  # header/footer. Only exposes deliberately-public keys.
  def settings
    return_success(
      company_name:  AppSetting.get('company.name', 'Rerock Realty'),
      logo_url:      AppSetting.get('branding.logo_url', ''),
      contact_email: AppSetting.get('company.email', ''),
      contact_phone: AppSetting.get('company.phone', ''),
      address:       AppSetting.get('company.address', ''),
      currency:      AppSetting.get('locale.currency', 'INR')
    )
  end

  # POST /api/public/enquiries — website lead capture (no auth).
  # Creates/updates a Customer lead, notifies every admin in-app, logs a
  # Requirement+Match so a property-specific enquiry appears in the admin's
  # Enquiry Pipeline, and if a referral code was carried in (?ref= link),
  # logs a Referral for that member.
  def enquire
    name    = params[:name].to_s.strip
    phone   = params[:phone].to_s.strip
    email   = params[:email].to_s.strip.downcase
    message = params[:message].to_s.strip
    return_errors!({ name: "Can't be blank" },  400) if name.empty?
    return_errors!({ phone: "Can't be blank" }, 400) if phone.empty?

    property = params[:property_id] && Property.where(id: params[:property_id].to_i, active: true).first

    # De-dupe on phone (then email) so repeat enquiries enrich one lead
    # instead of spawning duplicates.
    customer = Customer.where(active: true, phone: phone).first
    customer ||= email.empty? ? nil : Customer.where(active: true, email: email).first

    note_line = [
      "Website enquiry#{property ? " — #{property.title}" : ''}",
      message.empty? ? nil : message
    ].compact.join(': ')

    if customer
      customer.notes = [customer.notes.presence, note_line].compact.join("\n")
      customer.save
    else
      customer = Customer.new(
        name: name, phone: phone, email: email.presence,
        lead_type: 'enquiry', status: 'new', source: 'website', notes: note_line
      )
      return_errors!(customer.errors, 400) unless customer.save
    end

    if property
      ids = (customer.saved_property_ids || []).to_a
      unless ids.include?(property.id)
        customer.update(saved_property_ids: Sequel.pg_array(ids + [property.id], :integer))
      end
      ensure_match!(customer, property)
    end

    capture_referral!(customer, property)
    notify_admins!(customer, property, message)

    return_success('Thank you! Our team will contact you shortly.')
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!('Could not submit your enquiry. Please try again.', 400)
  end

  private

  # A property-specific enquiry must surface in the admin's Enquiry Pipeline,
  # which is backed by Match (not Customer) — same requirement+match creation
  # staff do manually via "Log Enquiry". Without this, a website enquiry only
  # ever became a Customer note + notification and never appeared there.
  def ensure_match!(customer, property)
    requirement = customer.requirements_dataset.where(active: true, status: 'open').first
    requirement ||= Requirement.create(
      customer_id: customer.id,
      transaction_type: property.transaction_type,
      status: 'open'
    )
    return if Match.where(requirement_id: requirement.id, property_id: property.id, active: true).first
    Match.create(
      requirement_id: requirement.id, property_id: property.id,
      status: 'New', priority: 'medium', assigned_user_id: customer.assigned_user_id
    )
  end

  # ?ref=MRK-XXXX links attribute the lead to a referral member (spec's
  # referral-capture workflow). Silently skipped when the code is unknown.
  def capture_referral!(customer, property)
    code = params[:ref].to_s.strip
    return if code.empty?
    member = Member.where(active: true, status: 'active', referral_code: code).first
    return unless member
    return if Referral.where(active: true, member_id: member.id, linked_customer_id: customer.id).first

    referral = Referral.new(
      member_id: member.id, referral_type: 'buyer', status: 'New',
      linked_customer_id: customer.id, linked_property_id: property&.id,
      date: Date.today, notes: 'Captured automatically from a website enquiry link.'
    )
    member.recalculate_tier! if referral.save
  end

  def notify_admins!(customer, property, message)
    title = property ? "New enquiry: #{property.title}" : 'New website enquiry'
    body  = "#{customer.name} (#{customer.phone})#{message.to_s.empty? ? '' : " — #{message}"}"
    User.where(active: true, role: %w[super_admin admin]).each do |admin|
      App::Services::Notifier.dispatch(
        recipient_id: admin.id, channel: 'in_app', title: title, message: body,
        linked_type: 'Customer', linked_id: customer.id, priority: 'high'
      )
    end
  end
end
