class Api::V1::SystemConnectorsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!, only: %i[create update test_connection pre_flight_analysis start_migration]

  def index
    page     = [ params[:page].to_i, 1 ].max
    per_page = 12
    scope    = SystemConnector.all.order(created_at: :desc)

    # Backward compatible: when no `page` param is given, return the legacy
    # bare array (existing frontend/tests may rely on the unpaginated shape).
    if params[:page].present?
      total = scope.count
      connectors = scope.limit(per_page).offset((page - 1) * per_page)
      render json: {
        connectors: connectors.as_json(methods: [ :provider_label ]),
        pagination: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: [ (total.to_f / per_page).ceil, 1 ].max,
        },
      }
    else
      render json: scope.as_json(methods: [ :provider_label ])
    end
  end

  def create
    connector = SystemConnector.new(connector_params)
    connector.status         = "idle"
    connector.assets_imported = 0

    if connector.save
      render json: connector.as_json(methods: [ :provider_label ]), status: :created
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    connector = SystemConnector.find(params[:id])
    params[:system_connector].delete(:auth_token) if params[:system_connector][:auth_token].blank?

    if connector.update(connector_params)
      render json: connector.as_json(methods: [ :provider_label ]), status: :ok
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/system_connectors/:id/refresh_token
  # Manually forces an IMS access-token refresh for a jwt_service_account connector.
  def refresh_token
    connector = SystemConnector.find(params[:id])
    return render json: { error: "Connector is not configured for JWT service-account credentials." }, status: :unprocessable_entity unless connector.credential_type == "jwt_service_account"

    connector.refresh_access_token!
    render json: {
      token_status:            connector.token_status,
      access_token_expires_at: connector.access_token_expires_at,
      last_token_refreshed_at: connector.last_token_refreshed_at,
    }
  rescue Ims::JwtTokenExchangeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/system_connectors/:id/revoke_token
  # Clears the cached access token. True revocation requires rotating the
  # client secret / key pair in the Adobe Developer Console — see model docs.
  def revoke_token
    connector = SystemConnector.find(params[:id])
    connector.revoke_token!
    render json: { token_status: connector.token_status }
  end

  # POST /api/v1/system_connectors/test_connection
  # Tests a connector config before saving. Routes to correct adapter per provider.
  def test_connection
    provider = params[:provider_type].to_s

    if params[:credential_type].to_s == "jwt_service_account"
      return test_jwt_connection(provider)
    end

    creds = {
      "endpoint"        => params[:endpoint],
      "auth_token"      => params[:auth_token],
      "cloud_name"      => params[:cloud_name],
      "brandfolder_key" => params[:brandfolder_key],
      "username"        => params[:username],
      "password"        => params[:password],
      "remote_path"     => params[:remote_path],
      "root_path"       => (params[:source_path] || params[:default_source_path]),
    }.compact_blank

    if creds["endpoint"].blank? && provider != "cloudinary"
      return render json: { success: false, message: "Endpoint and credentials are required." }, status: :bad_request
    end

    result = IngestionAdapters::Factory.test(provider, creds)

    if result[:success]
      render json: { success: true,  message: result[:message] }
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    render json: { success: false, message: e.message }, status: :bad_request
  end

  # POST /api/v1/system_connectors/pre_flight_analysis
  def pre_flight_analysis
    connector = SystemConnector.find(params[:id])
    connector.update!(default_source_path: params[:source_path]) if params[:source_path].present?
    PreFlightAnalysisWorker.perform_async(connector.id)
    render json: { message: "Pre-flight analysis started." }, status: :accepted
  end

  # POST /api/v1/system_connectors/:id/start_migration
  # Creates a new IngestionBatch and fires the extraction pipeline.
  # Accepts an optional `source_path` to scope the run to a single AEM (or
  # other provider) folder instead of migrating the whole connector root.
  def start_migration
    connector = SystemConnector.find(params[:id])
    return render json: { error: "Connector is not active." }, status: :unprocessable_entity unless connector.status == "active"

    source_path = params[:source_path].presence || connector.default_source_path
    # JWT-backed connectors deliberately do NOT snapshot a token onto the batch:
    # Factory#resolve_credentials falls back to connector#credentials_for_adapter
    # on every chunk fetch, which transparently refreshes the IMS access token
    # if it's expiring — so a multi-hour migration never stalls on a stale token.
    snapshot_credentials = connector.credential_type == "jwt_service_account" ? {} : connector.credentials_for_adapter(source_path: source_path)

    batch = IngestionBatch.create!(
      name:           "#{connector.provider_label} Migration — #{Time.current.strftime("%Y-%m-%d %H:%M")}",
      source_type:    connector.provider_type,
      connector_id:   connector.id,
      initiated_by_id: current_user.id,
      status:         :initializing,
      started_at:     Time.current,
      source_path:    source_path,
      source_credentials: snapshot_credentials
    )

    ExtractionWorker.perform_async(batch.id)
    render json: { message: "Migration started.", batch: batch.summary }, status: :accepted
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def connector_params
    permitted = params.require(:system_connector).permit(
      :name, :provider_type, :endpoint, :auth_token,
      :tdm_sanitation, :status, :concurrency_limit, :rps_limit,
      :credential_type, :default_source_path,
      credentials_payload: [ :client_id, :client_secret, :private_key, :technical_account_id,
                              :org_id, :ims_endpoint, :metascopes, :certificate_expiration_date, :email ]
    )

    # Convenience path: admins paste the raw JSON downloaded from the Adobe
    # Developer Console ("Generate JWT credential" screen) as-is, instead of
    # re-typing each field — normalize it into our credentials_payload shape.
    if params[:system_connector][:integration_json].present?
      permitted[:credentials_payload] = parse_integration_json(params[:system_connector][:integration_json])
      permitted[:credential_type] = "jwt_service_account"
    end

    permitted
  end

  def parse_integration_json(raw)
    data = raw.is_a?(String) ? JSON.parse(raw) : raw
    integration = data["integration"] || data
    tech = integration["technicalAccount"] || {}

    {
      "client_id"                    => tech["clientId"],
      "client_secret"                => tech["clientSecret"],
      "private_key"                  => integration["privateKey"],
      "technical_account_id"         => integration["id"],
      "org_id"                       => integration["org"],
      "ims_endpoint"                 => integration["imsEndpoint"],
      "metascopes"                   => integration["metascopes"],
      "certificate_expiration_date"  => integration["certificateExpirationDate"],
      "email"                        => integration["email"],
    }.compact
  rescue JSON::ParserError
    raise ActionController::BadRequest, "Invalid integration JSON payload."
  end

  def test_jwt_connection(provider)
    payload = parse_integration_json(params[:integration_json].presence || { "integration" => params.to_unsafe_h.slice("technicalAccount", "org", "id", "imsEndpoint", "metascopes", "privateKey") })

    scratch = SystemConnector.new(
      name: "connection-test", provider_type: provider, endpoint: params[:endpoint],
      credential_type: "jwt_service_account", credentials_payload: payload
    )

    unless scratch.valid?
      return render json: { success: false, message: scratch.errors.full_messages.join(", ") }, status: :bad_request
    end

    token = Ims::JwtTokenExchangeService.new(scratch).call
    creds = { "endpoint" => params[:endpoint], "auth_token" => token[:access_token], "root_path" => (params[:source_path] || params[:default_source_path]) }.compact_blank
    result = IngestionAdapters::Factory.test(provider, creds)

    if result[:success]
      render json: { success: true, message: result[:message] }
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  rescue Ims::JwtTokenExchangeService::Error => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end
end
