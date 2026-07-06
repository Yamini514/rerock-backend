require 'csv'

# CSV / XLSX import & export.
#   GET  /api/export/:entity?format=csv|xlsx   (staff; activity_logs super admin)
#   POST /api/import/:entity                   (super admin; multipart `file`)
class App::Services::DataTransfer < App::Services::Base
  MAX_IMPORT_ROWS = 2000
  ARRAY_SEPARATOR = '|' # array columns round-trip as pipe-joined strings

  # Per-entity export permissions (super_admin always allowed). The Viewer
  # is deliberately absent everywhere: read-only review does not include
  # bulk extraction of the contact book. Agents remain row-scoped below.
  EXPORT_ROLES = {
    'properties'    => %w[admin agent property_manager],
    'customers'     => %w[admin agent],
    'members'       => %w[admin referral_coordinator],
    'referrals'     => %w[admin referral_coordinator],
    'matches'       => %w[admin agent],
    'follow_ups'    => %w[admin agent property_manager referral_coordinator],
    'activity_logs' => %w[], # super_admin only (matches the old super_admin_only flag)
  }.freeze

  # Which columns leave/enter the system per entity. Import upserts on
  # `upsert_key` when present; entities without one always create.
  ENTITIES = {
    'properties' => {
      model: -> { App::Models::Property },
      columns: %w[
        id code title property_type transaction_type location city price area
        bedrooms bathrooms status facing floor age furnishing parking
        possession_status amenities approvals tags owner_name owner_contact
        source_notes confidential shared image images map_link brochure_link notes
        assigned_user_id created_at updated_at
      ],
      import_columns: %w[
        code title property_type transaction_type location city price area
        bedrooms bathrooms status facing floor age furnishing parking
        possession_status amenities approvals tags owner_name owner_contact
        source_notes image images map_link brochure_link notes assigned_user_id
      ],
      array_columns: %w[amenities approvals tags images],
      upsert_key: 'code',
    },
    'customers' => {
      model: -> { App::Models::Customer },
      columns: %w[
        id name email phone alt_phone lead_type city source preferred_language
        status assigned_user_id shared notes last_followup_at next_followup_at
        created_at updated_at
      ],
      import_columns: %w[
        name email phone alt_phone lead_type city source preferred_language
        status assigned_user_id notes
      ],
      array_columns: [],
      upsert_key: 'phone',
    },
    'members' => {
      model: -> { App::Models::Member },
      columns: %w[
        id name email phone member_type tier status referral_code
        relationship_notes created_at updated_at
      ],
      import_columns: %w[name email phone member_type status relationship_notes],
      array_columns: [],
      upsert_key: 'phone',
    },
    'referrals' => {
      model: -> { App::Models::Referral },
      columns: %w[
        id member_id referral_type linked_customer_id linked_property_id
        expected_value closure_value status date notes created_at updated_at
      ],
      import_columns: %w[
        member_id referral_type linked_customer_id linked_property_id
        expected_value closure_value status date notes
      ],
      array_columns: [],
      upsert_key: nil,
    },
    # Report-style exports (no import).
    'matches' => {
      model: -> { App::Models::Match },
      columns: %w[
        id requirement_id property_id score score_band explanation status
        priority assigned_user_id notes created_at updated_at
      ],
      import_columns: nil,
      array_columns: [],
      upsert_key: nil,
    },
    'follow_ups' => {
      model: -> { App::Models::FollowUp },
      columns: %w[
        id linked_type linked_id due_date priority owner_id status notes
        completed_at created_at updated_at
      ],
      import_columns: nil,
      array_columns: [],
      upsert_key: nil,
    },
    'activity_logs' => {
      model: -> { App::Models::ActivityLog },
      columns: %w[id user_id user_email action entity_type entity_id changes ip details created_at],
      import_columns: nil,
      array_columns: [],
      upsert_key: nil,
      super_admin_only: true,
    },
  }.freeze

  def export
    entity, config = entity_config!
    u = current_user_obj
    unless u&.super_admin? || EXPORT_ROLES.fetch(entity, []).include?(u&.role)
      return_errors!('Forbidden', 403)
    end

    columns = config[:columns]
    # Property owner/source fields follow the same per-row confidentiality
    # rule as Property#to_pos: hidden on confidential rows for everyone but
    # a super admin.
    mask_confidential = entity == 'properties' && !current_user_obj&.super_admin?
    rows = export_dataset(entity, config).all.map do |record|
      columns.map do |col|
        if mask_confidential && record.confidential && Property::CONFIDENTIAL_FIELDS.include?(col)
          nil
        else
          encode_cell(record.send(col))
        end
      end
    end

    ActivityLog.record!(action: 'export', details: "Exported #{rows.size} #{entity} row(s) as #{format}")

    filename = "#{entity}-#{Date.today.iso8601}.#{format}"
    if format == 'xlsx'
      send_file(xlsx_body(entity, columns, rows), filename,
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    else
      body = CSV.generate { |csv| csv << columns; rows.each { |row| csv << row } }
      send_file(body, filename, 'text/csv')
    end
  end

  def import
    entity, config = entity_config!
    return_errors!("Import is not supported for #{entity}.", 400) unless config[:import_columns]

    file = rp[:file]
    return_errors!('No file provided (multipart field: file).', 400) unless file.is_a?(Hash) && file[:tempfile]

    rows = parse_rows(file)
    return_errors!('The file has no data rows.', 400) if rows.empty?
    return_errors!("Too many rows (max #{MAX_IMPORT_ROWS} per import).", 400) if rows.size > MAX_IMPORT_ROWS

    model  = config[:model].call
    key    = config[:upsert_key]
    result = { created: 0, updated: 0, failed: [] }

    rows.each_with_index do |row, idx|
      data = row.slice(*config[:import_columns])
      config[:array_columns].each do |col|
        next unless data.key?(col)
        list = data[col].to_s.split(ARRAY_SEPARATOR).map(&:strip).reject(&:empty?)
        data[col] = Sequel.pg_array(list, :text)
      end

      record = key && data[key].present? ? model.where(key.to_sym => data[key]).first : nil
      is_new = record.nil?
      record ||= model.new

      begin
        record.set_fields(data, data.keys, missing: :skip)
        if record.save
          is_new ? result[:created] += 1 : result[:updated] += 1
        else
          result[:failed] << { row: idx + 2, errors: record.errors } # +2 = header + 1-index
        end
      rescue => e
        result[:failed] << { row: idx + 2, errors: e.message }
      end
    end

    ActivityLog.record!(
      action: 'import',
      details: "Imported #{entity}: #{result[:created]} created, #{result[:updated]} updated, #{result[:failed].size} failed"
    )
    return_success(result)
  end

  private

  def entity_config!
    entity = rp[:entity].to_s
    config = ENTITIES[entity] || return_errors!("Unknown entity: #{entity}", 404)
    [entity, config]
  end

  def format
    @format ||= qs[:format].to_s == 'xlsx' ? 'xlsx' : 'csv'
  end

  # Mirrors each entity's list scoping so an export can never contain rows
  # the caller's list view wouldn't show (agents: assigned + shared pool;
  # operational roles: own follow-ups only).
  def export_dataset(entity, config)
    model = config[:model].call
    ds = entity == 'activity_logs' ? model.dataset : model.where(active: true)
    u = current_user_obj
    if u&.agent?
      if model.columns.include?(:shared)
        ds = ds.where(Sequel.|({ assigned_user_id: u.id }, { shared: true }))
      elsif model.columns.include?(:assigned_user_id)
        ds = ds.where(assigned_user_id: u.id)
      end
    end
    if entity == 'follow_ups' && u && %w[agent property_manager referral_coordinator].include?(u.role)
      ds = ds.where(owner_id: u.id)
    end
    ds.order(Sequel.desc(:created_at)).limit(10_000)
  end

  def encode_cell(value)
    case value
    when Array then value.join(ARRAY_SEPARATOR)
    when Time, DateTime then value.iso8601
    else value.respond_to?(:to_ary) ? value.to_ary.join(ARRAY_SEPARATOR) : value
    end
  end

  def xlsx_body(sheet_name, columns, rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: sheet_name.capitalize[0, 31]) do |sheet|
      sheet.add_row(columns)
      rows.each { |row| sheet.add_row(row) }
    end
    package.to_stream.read
  end

  def send_file(body, filename, content_type)
    request.halt(200, {
      'Content-Type' => content_type,
      'Content-Disposition' => "attachment; filename=\"#{filename}\"",
    }, body)
  end

  # Returns an array of {header => string-value} hashes from CSV or XLSX.
  def parse_rows(file)
    filename = file[:filename].to_s.downcase
    if filename.end_with?('.xlsx')
      sheet = Roo::Excelx.new(file[:tempfile].path)
      headers = sheet.row(sheet.first_row).map { |h| h.to_s.strip }
      (sheet.first_row + 1..sheet.last_row).map do |i|
        headers.zip(sheet.row(i).map { |v| xlsx_cell_to_s(v) }).to_h
      end
    else
      table = CSV.parse(file[:tempfile].read.force_encoding('UTF-8'), headers: true)
      table.map { |row| row.to_h.transform_keys { |k| k.to_s.strip } }
    end
  rescue CSV::MalformedCSVError => e
    return_errors!("Could not parse the file: #{e.message}", 400)
  end

  # Roo returns numeric cells as Floats — "8500000.0" would fail integer
  # typecasting, so whole floats are normalized back to integer strings.
  def xlsx_cell_to_s(value)
    return nil if value.nil?
    return value.to_i.to_s if value.is_a?(Float) && value % 1 == 0
    value.to_s
  end
end
