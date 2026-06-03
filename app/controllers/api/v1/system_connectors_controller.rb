class Api::V1::SystemConnectorsController < ApplicationController
  # Require admin authentication in production

  def index
    connectors = SystemConnector.all.order(created_at: :desc)
    render json: connectors
  end

  def create
    connector = SystemConnector.new(connector_params)
    connector.status = 'idle'
    connector.assets_imported = 0
    connector.last_sync = nil

    if connector.save
      render json: connector, status: :created
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    connector = SystemConnector.find(params[:id])

    # If the user leaves the token blank on edit, don't overwrite the existing token
    if params[:system_connector][:auth_token].blank?
      params[:system_connector].delete(:auth_token)
    end

    if connector.update(connector_params)
      render json: connector, status: :ok
    else
      render json: { errors: connector.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def test_connection
    endpoint = params[:endpoint]
    token = params[:auth_token]
    provider = params[:provider_type]

    # Fast exit if fields are missing
    if endpoint.blank? || token.blank?
      return render json: { success: false, message: "Endpoint and Auth Token are required." }, status: :bad_request
    end

    begin
      # In a real scenario, you would use Net::HTTP to ping the actual endpoint.
      # For now, we simulate a network check with a slight delay.
      sleep(1.5)

      # Mock validation logic
      if token.length > 5 && endpoint.starts_with?('http', 's3://')
        render json: { success: true, message: "Successfully authenticated with #{provider}." }, status: :ok
      else
        render json: { success: false, message: "Connection refused. Invalid token or endpoint format." }, status: :unauthorized
      end
    rescue => e
      render json: { success: false, message: "Network error: #{e.message}" }, status: :internal_server_error
    end
  end

  def pre_flight_analysis
    connector = SystemConnector.find(params[:id])

    # Trigger a lightweight worker that only pulls JSON headers, not binaries
    PreFlightAnalysisWorker.perform_async(connector.id)

    render json: { message: "Analysis started. Data will be ready in a few moments." }, status: :accepted
  end

  private

  def connector_params
    params.require(:system_connector).permit(
      :name, :provider_type, :endpoint, :auth_token, :tdm_sanitation, :status
    )
  end
end