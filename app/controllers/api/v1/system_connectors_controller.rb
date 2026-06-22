class Api::V1::SystemConnectorsController < ApplicationController
  before_action :authenticate_user!

  def index
    connectors = SystemConnector.all.order(created_at: :desc)
    render json: connectors.as_json(methods: [:provider_label])
  end

  def create
    connector = SystemConnector.new(connector_params)
    connector.status         = 'idle'
    connector.assets_imported = 0

    if connector.save
      render json: connector.as_json(methods: [:provider_label]), status: :created
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    connector = SystemConnector.find(params[:id])
    params[:system_connector].delete(:auth_token) if params[:system_connector][:auth_token].blank?

    if connector.update(connector_params)
      render json: connector.as_json(methods: [:provider_label]), status: :ok
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/system_connectors/test_connection
  # Tests a connector config before saving. Routes to correct adapter per provider.
  def test_connection
    provider = params[:provider_type].to_s
    creds    = {
      'endpoint'        => params[:endpoint],
      'auth_token'      => params[:auth_token],
      'cloud_name'      => params[:cloud_name],
      'brandfolder_key' => params[:brandfolder_key],
      'username'        => params[:username],
      'password'        => params[:password],
      'remote_path'     => params[:remote_path]
    }.compact_blank

    if creds['endpoint'].blank? && provider != 'cloudinary'
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
    PreFlightAnalysisWorker.perform_async(connector.id)
    render json: { message: "Pre-flight analysis started." }, status: :accepted
  end

  # POST /api/v1/system_connectors/:id/start_migration
  # Creates a new IngestionBatch and fires the extraction pipeline.
  def start_migration
    connector = SystemConnector.find(params[:id])
    return render json: { error: "Connector is not active." }, status: :unprocessable_entity unless connector.status == 'active'

    batch = IngestionBatch.create!(
      name:           "#{connector.provider_label} Migration — #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      source_type:    connector.provider_type,
      connector_id:   connector.id,
      initiated_by_id: current_user.id,
      status:         :initializing,
      started_at:     Time.current,
      source_credentials: { 'endpoint' => connector.endpoint, 'auth_token' => connector.auth_token }
    )

    ExtractionWorker.perform_async(batch.id)
    render json: { message: "Migration started.", batch: batch.summary }, status: :accepted
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def connector_params
    params.require(:system_connector).permit(
      :name, :provider_type, :endpoint, :auth_token,
      :tdm_sanitation, :status, :concurrency_limit, :rps_limit
    )
  end
end