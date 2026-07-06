# Seed script — resets the database to one login per role PLUS a small,
# deterministic sample dataset in which every RBAC test case has a concrete
# record to verify against (agent isolation, shared pool, confidential
# masking, tier auto-calculation, due/overdue follow-ups, per-role alerts).
#
# This is destructive: it clears every domain table and every user account
# before recreating the canonical accounts and fixtures.
#
# Run with:  bundle exec rake db:seed
#
# Safe to re-run — it always converges to the same accounts and fixtures.
# Follow-up due dates are relative to today and member tiers are derived by
# recalculate_tier! from the configured rules, so time-sensitive and
# computed test cases stay valid on every run.

include App::Models

puts "Resetting Merock Realty database..."

# ── Wipe all sample/demo data ──────────────────────────────────────────────
# Order matters where a real FK exists (requirements -> customers cascades on
# delete); the rest have no DB-level FK, so they're cleared explicitly.
App::Models::ActivityLog.dataset.delete
App::Models::NotificationLog.dataset.delete
App::Models::FollowUp.dataset.delete
App::Models::Match.dataset.delete
App::Models::Referral.dataset.delete
App::Models::Member.dataset.delete
App::Models::Requirement.dataset.delete
App::Models::Customer.dataset.delete
App::Models::Property.dataset.delete
App::Models::User.dataset.delete
puts "  cleared all domain tables and user accounts."

# ── One login per role (dev fixtures — change these before production) ────
# SRS mapping: admin = Business Owner, agent = Sales Manager. A second agent
# exists purely to verify cross-agent record isolation.
DEMO_USERS = [
  { full_name: 'Owner Account',        email: 'owner@example.com',       phone_number: '+91 90000 00000', role: 'super_admin',          password: 'owner123'    },
  { full_name: 'Business Owner',       email: 'admin@example.com',       phone_number: '+91 90000 00001', role: 'admin',                password: 'admin123'    },
  { full_name: 'Sales Manager One',    email: 'agent@example.com',       phone_number: '+91 90000 00002', role: 'agent',                password: 'agent123'    },
  { full_name: 'Sales Manager Two',    email: 'agent2@example.com',      phone_number: '+91 90000 00005', role: 'agent',                password: 'agent2123'   },
  { full_name: 'Property Manager',     email: 'propman@example.com',     phone_number: '+91 90000 00006', role: 'property_manager',     password: 'propman123'  },
  { full_name: 'Referral Coordinator', email: 'coordinator@example.com', phone_number: '+91 90000 00007', role: 'referral_coordinator', password: 'coord1234'   },
  { full_name: 'Read-only Viewer',     email: 'viewer@example.com',      phone_number: '+91 90000 00008', role: 'viewer',               password: 'viewer123'   },
  { full_name: 'Client User',          email: 'user@example.com',        phone_number: '+91 90000 00003', role: 'client',               password: 'user1234'    },
  { full_name: 'Member User',          email: 'member@example.com',      phone_number: '+91 90000 00004', role: 'member',               password: 'member123'   },
]

DEMO_USERS.each do |attrs|
  u = App::Models::User.new
  u.set(attrs.except(:password))
  u.password = attrs[:password]
  u.save
end

puts "  users: #{App::Models::User.count} (one per role, two agents)"

# ── Configuration seeding (idempotent, NON-destructive) ────────────────────
# Settings, master data, and templates are only inserted when missing, so a
# Super Admin's edits survive re-running the seed. The wipe section above
# deliberately does not touch these tables.

def seed_setting(key, value, group:, label:, description: nil)
  return if App::Models::AppSetting.where(setting_key: key).first
  App::Models::AppSetting.set(key, value, group: group, label: label, description: description)
end

# Company / branding / locale / email / business
seed_setting('company.name',    'Rerock Realty',            group: 'company',  label: 'Company Name')
seed_setting('company.email',   'hello@rerockrealty.com',   group: 'company',  label: 'Contact Email')
seed_setting('company.phone',   '',                         group: 'company',  label: 'Contact Phone')
seed_setting('company.address', '',                         group: 'company',  label: 'Office Address')
seed_setting('branding.logo_url', '',                       group: 'branding', label: 'Logo URL')
seed_setting('locale.timezone',    'Asia/Kolkata',          group: 'locale',   label: 'Timezone')
seed_setting('locale.date_format', 'DD MMM YYYY',           group: 'locale',   label: 'Date Format')
seed_setting('locale.currency',    'INR',                   group: 'locale',   label: 'Currency')
seed_setting('locale.language',    'en',                    group: 'locale',   label: 'Language')
seed_setting('email.from_address', '',                      group: 'email',    label: 'From Address')
seed_setting('email.from_name',    'Rerock Realty',         group: 'email',    label: 'From Name')
seed_setting('business.default_followup_priority', 'medium', group: 'business', label: 'Default Follow-up Priority')

# Matching engine (seeded from the current code constants — identical behavior
# until a Super Admin edits them)
seed_setting('matching.weights', App::Models::Match::WEIGHTS,
             group: 'matching', label: 'Scoring Weights',
             description: 'Weighted criteria; must total 100.')
seed_setting('matching.score_bands', App::Models::Match::BAND_THRESHOLDS.to_h,
             group: 'matching', label: 'Score Bands',
             description: 'Minimum score per band; below the lowest is Not Recommended.')
seed_setting('matching.min_score', 25,
             group: 'matching', label: 'Minimum Score to Save a Match')
seed_setting('matching.auto_recalculate', false,
             group: 'matching', label: 'Auto-recalculate on Property/Requirement Changes')

# Elite tiers (seeded from Member::TIER_RULES)
seed_setting('elite_tiers.rules',
             App::Models::Member::TIER_RULES.map { |(t, c, v)| { tier: t, min_count: c, min_value: v } },
             group: 'elite_tiers', label: 'Tier Thresholds',
             description: 'A member qualifies for a tier by referral count OR converted value; checked highest first.')
seed_setting('elite_tiers.points_per_referral', 10, group: 'elite_tiers', label: 'Points per Converted Referral')
seed_setting('elite_tiers.reward_notes', '', group: 'elite_tiers', label: 'Reward Rules / Notes')

# Security policy
seed_setting('security.password_min_length',   8,     group: 'security', label: 'Minimum Password Length')
seed_setting('security.password_require_mixed', false, group: 'security', label: 'Require Letters and Numbers')

puts "  settings: #{App::Models::AppSetting.count}"

# Master data — seeded from the legacy model constants so validation behavior
# is unchanged on day one. Status-type categories are system rows: their
# stored values are referenced by code (scoring, dashboards, public site).
def seed_master(category, values, system: false)
  values.each_with_index do |v, i|
    next if App::Models::MasterDataItem.where(category: category, value: v).first
    App::Models::MasterDataItem.create(
      category: category, value: v,
      label: v.to_s.split('_').map(&:capitalize).join(' '),
      sort_order: i, is_system: system
    )
  end
end

seed_master('property_types',    App::Models::Property::PROPERTY_TYPES)
seed_master('property_statuses', App::Models::Property::STATUSES,  system: true)
seed_master('customer_statuses', App::Models::Customer::STATUSES,  system: true)
seed_master('member_types',      App::Models::Member::MEMBER_TYPES, system: true)
seed_master('followup_statuses', App::Models::FollowUp::STATUSES,  system: true)
seed_master('referral_sources',  App::Models::Referral::REFERRAL_TYPES, system: true)
seed_master('lead_sources',      %w[website portal referral walk_in phone social_media], system: true)
seed_master('tags',              %w[featured premium hot_deal new_launch])

puts "  master data: #{App::Models::MasterDataItem.count} items"

# Starter notification templates
[
  { name: 'enquiry_received', channel: 'in_app',
    subject: 'New enquiry: {{property_title}}',
    body: '{{customer_name}} ({{customer_phone}}) enquired{{message_suffix}}',
    variables: %w[property_title customer_name customer_phone message_suffix].to_json,
    description: 'Shown to admins when a website enquiry arrives.' },
  { name: 'password_reset', channel: 'email',
    subject: 'Reset your {{company_name}} password',
    body: "Hi {{name}},\n\nUse the link below to reset your password. It expires in 2 hours.\n\n{{reset_link}}\n\nIf you didn't request this, you can ignore this email.",
    variables: %w[company_name name reset_link].to_json,
    description: 'Sent when a user requests a password reset.' },
  { name: 'match_alert', channel: 'email',
    subject: 'New high match: {{property_title}}',
    body: "Hi {{name}},\n\nA new {{score_band}} match ({{score}}%) was found between {{customer_name}} and {{property_title}}.\n\n{{explanation}}",
    variables: %w[name property_title customer_name score score_band explanation].to_json,
    description: 'Optional alert for strong matches.' },
].each do |attrs|
  next if App::Models::NotificationTemplate.where(name: attrs[:name]).first
  App::Models::NotificationTemplate.create(attrs)
end

puts "  templates: #{App::Models::NotificationTemplate.count}"

# ═══════════════════════════════════════════════════════════════════════════
# SAMPLE DATA — one record per RBAC test case.
# Placed after master data so master-data-driven validations pass.
# ═══════════════════════════════════════════════════════════════════════════

users = App::Models::User.to_hash(:email)
sa      = users['owner@example.com']
owner   = users['admin@example.com']
agent1  = users['agent@example.com']
agent2  = users['agent2@example.com']
propman = users['propman@example.com']
coord   = users['coordinator@example.com']
viewer  = users['viewer@example.com']

def txt_array(list) = Sequel.pg_array(list, :text)

# ── Properties ─────────────────────────────────────────────────────────────
# P1: agent1's own listing            -> agent1 sees it, agent2 must NOT.
# P2: agent2's own listing            -> isolation check from the other side.
# P3: shared pool                     -> BOTH agents see/work it (WI-9).
# P4: confidential                    -> owner/source fields visible to
#                                        super_admin only; everyone else masked.
# P5: property manager's listing      -> PM write test target.
# P6: draft, unassigned               -> visible to admin/PM/viewer, not agents.
props = {}
[
  { key: :p1, code: 'MRK-SKY001', title: 'Skyline Heights 3BHK',      property_type: 'Apartment',  transaction_type: 'buy',  location: 'Indiranagar',  city: 'Bengaluru', price: 9_500_000,  area: 1450, bedrooms: 3, bathrooms: 3, status: 'available',        assigned_user_id: agent1.id,  amenities: txt_array(%w[parking lift gym]), tags: txt_array(%w[featured]) },
  { key: :p2, code: 'MRK-PLM002', title: 'Palm Grove Villa',          property_type: 'Villa',      transaction_type: 'buy',  location: 'Whitefield',   city: 'Bengaluru', price: 21_000_000, area: 3200, bedrooms: 4, bathrooms: 5, status: 'available',        assigned_user_id: agent2.id,  amenities: txt_array(%w[garden pool parking]) },
  { key: :p3, code: 'MRK-HBR003', title: 'Harbor View Penthouse',     property_type: 'Penthouse',  transaction_type: 'buy',  location: 'Indiranagar',  city: 'Bengaluru', price: 14_000_000, area: 2100, bedrooms: 3, bathrooms: 4, status: 'available',        assigned_user_id: owner.id,   shared: true, amenities: txt_array(%w[terrace parking lift]) },
  { key: :p4, code: 'MRK-CNF004', title: 'Heritage Bungalow (Off-market)', property_type: 'Villa', transaction_type: 'buy',  location: 'Sadashivanagar', city: 'Bengaluru', price: 55_000_000, area: 6000, bedrooms: 5, bathrooms: 6, status: 'under_discussion', assigned_user_id: owner.id, confidential: true, owner_name: 'K. Reddy (family trust)', owner_contact: '+91 98450 11111', source_notes: 'Do not circulate — owner wants a quiet sale.', notes: 'Negotiation sensitive.' },
  { key: :p5, code: 'MRK-MGR005', title: 'MG Road Commercial Block',  property_type: 'Commercial', transaction_type: 'rent', location: 'MG Road',      city: 'Bengaluru', price: 450_000,    area: 5200, status: 'under_discussion', assigned_user_id: propman.id, approvals: txt_array(%w[occupancy_certificate fire_noc]) },
  { key: :p6, code: 'MRK-LKS006', title: 'Lakeside Plot',             property_type: 'Plot',       transaction_type: 'buy',  location: 'Hennur',       city: 'Bengaluru', price: 6_800_000,  area: 2400, status: 'draft' },
].each do |attrs|
  key = attrs.delete(:key)
  props[key] = App::Models::Property.create(attrs)
end
puts "  properties: #{App::Models::Property.count} (own/shared/confidential/PM/draft cases)"

# ── Customers + requirements ───────────────────────────────────────────────
# C1: agent1's buyer (with requirement) -> matching + isolation cases.
# C2: agent2's tenant                   -> agent1 must NOT see.
# C3: shared investor                   -> both agents see/work it (WI-9).
# C4: owner's seller                    -> agents must NOT see.
# C5: agent1's walk-in enquiry          -> list/filter/search cases.
custs = {}
[
  { key: :c1, name: 'Rahul Verma',    phone: '+91 98860 10001', email: 'rahul.verma@example.com', lead_type: 'buyer',    city: 'Bengaluru', source: 'website',  status: 'qualified', assigned_user_id: agent1.id },
  { key: :c2, name: 'Sneha Iyer',     phone: '+91 98860 10002', email: 'sneha.iyer@example.com',  lead_type: 'tenant',   city: 'Bengaluru', source: 'referral', status: 'contacted', assigned_user_id: agent2.id },
  { key: :c3, name: 'Amit Shah',      phone: '+91 98860 10003', email: 'amit.shah@example.com',   lead_type: 'investor', city: 'Mumbai',    source: 'referral', status: 'new',       shared: true },
  { key: :c4, name: 'Priya Nair',     phone: '+91 98860 10004', email: 'priya.nair@example.com',  lead_type: 'seller',   city: 'Bengaluru', source: 'walk_in',  status: 'new',       assigned_user_id: owner.id },
  { key: :c5, name: 'Walk-in Buyer',  phone: '+91 98860 10005',                                    lead_type: 'enquiry',  city: 'Bengaluru', source: 'walk_in',  status: 'contacted', assigned_user_id: agent1.id },
].each do |attrs|
  key = attrs.delete(:key)
  custs[key] = App::Models::Customer.create(attrs)
end

reqs = {}
reqs[:r1] = App::Models::Requirement.create(
  customer_id: custs[:c1].id, transaction_type: 'buy', status: 'open',
  property_types: txt_array(%w[Apartment Penthouse]), locations: txt_array(%w[Indiranagar]),
  budget_min: 8_000_000, budget_max: 15_000_000, bedrooms: 3, urgency: 'high',
  amenities: txt_array(%w[parking lift])
)
reqs[:r2] = App::Models::Requirement.create(
  customer_id: custs[:c2].id, transaction_type: 'rent', status: 'open',
  property_types: txt_array(%w[Villa Apartment]), locations: txt_array(%w[Whitefield]),
  budget_min: 60_000, budget_max: 120_000, bedrooms: 4, urgency: 'medium'
)
reqs[:r3] = App::Models::Requirement.create(
  customer_id: custs[:c3].id, transaction_type: 'invest', status: 'open',
  property_types: txt_array(%w[Plot Commercial]), locations: txt_array(%w[Hennur]),
  budget_min: 5_000_000, budget_max: 10_000_000, urgency: 'low'
)
puts "  customers: #{App::Models::Customer.count}, requirements: #{App::Models::Requirement.count}"

# ── Members + referrals (Referral Coordinator's domain) ────────────────────
# M1 converts 260k across 2 closures -> tier auto-derives to Gold (value rule).
# M2 has 3 referrals                 -> tier auto-derives to Silver (count rule).
# M3 has 1 new referral              -> stays Standard.
# The member portal login (member@example.com) is linked to M1 so
# GET /me/referrals returns real history.
m1 = App::Models::Member.create(name: 'Rajesh Kumar', phone: '+91 99000 20001', email: 'rajesh.kumar@example.com', member_type: 'source', status: 'active', relationship_notes: 'Long-time channel partner.')
m2 = App::Models::Member.create(name: 'Meera Pillai', phone: '+91 99000 20002', email: 'meera.pillai@example.com', member_type: 'investor', status: 'active')
m3 = App::Models::Member.create(name: 'Vikram Singh', phone: '+91 99000 20003', email: 'vikram.singh@example.com', member_type: 'buyer', status: 'active')
users['member@example.com'].update(member_id: m1.id)

[
  { member_id: m1.id, referral_type: 'buyer',    status: 'Converted',   expected_value: 150_000, closure_value: 180_000, linked_customer_id: custs[:c1].id, notes: 'Closed with Skyline Heights purchase.', date: Date.today - 40 },
  { member_id: m1.id, referral_type: 'property', status: 'Converted',   expected_value: 100_000, closure_value: 80_000,  linked_property_id: props[:p3].id, notes: 'Sourced the Harbor View listing.',     date: Date.today - 25 },
  { member_id: m1.id, referral_type: 'seller',   status: 'In Progress', expected_value: 90_000,  linked_customer_id: custs[:c4].id, date: Date.today - 10 },
  { member_id: m1.id, referral_type: 'buyer',    status: 'New',         expected_value: 50_000,  date: Date.today - 2 },
  { member_id: m2.id, referral_type: 'buyer',    status: 'Converted',   expected_value: 60_000,  closure_value: 60_000, notes: 'Rental deal closed.', date: Date.today - 30 },
  { member_id: m2.id, referral_type: 'investor', status: 'Contacted',   expected_value: 75_000,  linked_customer_id: custs[:c3].id, date: Date.today - 12 },
  { member_id: m2.id, referral_type: 'buyer',    status: 'Reviewed',    date: Date.today - 5 },
  { member_id: m3.id, referral_type: 'buyer',    status: 'New',         expected_value: 40_000, date: Date.today - 1 },
].each { |attrs| App::Models::Referral.create(attrs) }

# Auto-update: derive tiers from the configured rules (never hardcode them).
[m1, m2, m3].each(&:recalculate_tier!)
puts "  members: #{App::Models::Member.count} (tiers auto-calculated: #{[m1, m2, m3].map { |m| "#{m.name.split.first}=#{m.refresh.tier}" }.join(', ')})"

# ── Matches (engine-shaped fixtures) ───────────────────────────────────────
# Assigned mirrors the engine rule: match follows the customer's agent.
# Includes each band + a Closed one (with the required note) so the matching
# dashboard, filters, and status flows all have data.
[
  { requirement_id: reqs[:r1].id, property_id: props[:p1].id, score: 88, status: 'Shortlisted', explanation: 'Location matches Indiranagar; Within budget; Apartment matches preference; Size/bedrooms fit.' },
  { requirement_id: reqs[:r1].id, property_id: props[:p3].id, score: 64, status: 'New',         explanation: 'Location matches Indiranagar; Within budget; Penthouse matches preference.' },
  { requirement_id: reqs[:r2].id, property_id: props[:p2].id, score: 55, status: 'Contacted',   explanation: 'Location matches Whitefield; Size/bedrooms fit.' },
  { requirement_id: reqs[:r3].id, property_id: props[:p6].id, score: 42, status: 'New',         explanation: 'Location matches Hennur; Within budget.' },
  { requirement_id: reqs[:r3].id, property_id: props[:p5].id, score: 51, status: 'Closed',      explanation: 'Commercial investment fit.', notes: 'Investor signed a 5-year lease.' },
].each do |attrs|
  req = App::Models::Requirement[attrs[:requirement_id]]
  App::Models::Match.create(attrs.merge(
    score_band: App::Models::Match.band_for(attrs[:score]),
    priority: 'medium',
    assigned_user_id: req.customer&.assigned_user_id
  ))
end
puts "  matches: #{App::Models::Match.count} (High/Medium/Low bands, one Closed)"

# ── Follow-ups (owner-scoped per operational role) ─────────────────────────
# Relative dates keep due-today/overdue cases true on every reseed.
[
  { owner: agent1,  linked_type: 'Customer', linked_id: custs[:c1].id, due: Date.today - 2, status: 'pending',   priority: 'high',   notes: 'OVERDUE case: call Rahul about shortlist.' },
  { owner: agent1,  linked_type: 'Property', linked_id: props[:p1].id, due: Date.today,     status: 'pending',   priority: 'medium', notes: 'DUE-TODAY case: confirm site visit slot.' },
  { owner: agent1,  linked_type: 'Customer', linked_id: custs[:c5].id, due: Date.today - 7, status: 'completed', priority: 'low',    notes: 'COMPLETED case: sent brochure.' },
  { owner: agent2,  linked_type: 'Customer', linked_id: custs[:c2].id, due: Date.today,     status: 'pending',   priority: 'high',   notes: 'Agent-2-only case: Sneha rent shortlist.' },
  { owner: propman, linked_type: 'Property', linked_id: props[:p5].id, due: Date.today + 1, status: 'pending',   priority: 'medium', notes: 'PM case: update possession status after fit-out.' },
  { owner: coord,   linked_type: 'Referral', linked_id: App::Models::Referral.where(member_id: m1.id, status: 'New').first.id, due: Date.today, status: 'pending', priority: 'high', notes: 'Coordinator case: qualify Rajesh\'s new referral.' },
  { owner: owner,   linked_type: 'Customer', linked_id: custs[:c4].id, due: Date.today + 5, status: 'pending',   priority: 'low',    notes: 'Owner case: review Priya listing mandate.' },
].each do |f|
  App::Models::FollowUp.create(
    linked_type: f[:linked_type], linked_id: f[:linked_id], due_date: f[:due].to_time,
    owner_id: f[:owner].id, status: f[:status], priority: f[:priority], notes: f[:notes]
  )
end
puts "  follow-ups: #{App::Models::FollowUp.count} (overdue/due-today/completed per role)"

# ── In-app alerts (one per staff role — recipient scoping test) ────────────
[
  { recipient: agent1.id,  title: 'New high match',            message: 'Skyline Heights 3BHK scored 88 for Rahul Verma.', priority: 'high'   },
  { recipient: agent2.id,  title: 'Follow-up due',             message: 'Sneha Iyer follow-up is due today.',              priority: 'medium' },
  { recipient: propman.id, title: 'Listing review',            message: 'MG Road Commercial Block needs a status update.', priority: 'medium' },
  { recipient: coord.id,   title: 'New referral logged',       message: 'Rajesh Kumar submitted a new buyer referral.',    priority: 'high'   },
  { recipient: viewer.id,  title: 'Weekly review ready',       message: 'Dashboards refreshed for your weekly review.',    priority: 'low'    },
  { recipient: owner.id,   title: 'Monthly pipeline summary',  message: '5 open enquiries, 1 closed deal this month.',     priority: 'medium' },
  { recipient: sa.id,      title: 'System check',              message: 'Seed data loaded successfully.',                  priority: 'low'    },
].each do |attrs|
  App::Models::NotificationLog.create(attrs.merge(channel: 'in_app', read: false))
end
puts "  alerts: #{App::Models::NotificationLog.count} (one per staff login)"

puts 'Reset complete. Sample data covers every role test case:'
puts '  agent isolation (P1/P2, C1/C2) · shared pool (P3, C3) · confidential masking (P4)'
puts '  PM listing (P5) · tier auto-calc (Gold/Silver/Standard) · member portal history (M1)'
puts '  match bands + Closed note · overdue/due-today follow-ups · per-role alerts'
