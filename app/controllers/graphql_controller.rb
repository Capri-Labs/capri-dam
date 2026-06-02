class GraphqlController < ApplicationController
  skip_before_action :verify_authenticity_token

  # 1. Add the "unless" condition to your authentication lock
  before_action :authenticate_hybrid!, unless: :introspection_query?

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    context = {
      current_user: current_user,
      session_id: session.id
    }

    # Dynamically apply security limits
    is_introspection = introspection_query?

    result = HeadlessDamSchema.execute(
      query,
      variables: variables,
      context: context,
      operation_name: operation_name,
      max_depth: is_introspection ? nil : 6,
      max_complexity: is_introspection ? nil : 200
    )

    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  private

  # 2. Define the security bypass logic
  def introspection_query?
    # Only allow unauthenticated schema reads in development.
    # In production, this returns false, meaning the API remains 100% locked.
    Rails.env.development? && params[:operationName] == 'IntrospectionQuery'
  end

  def prepare_variables(variables_param)
    case variables_param
    when String then variables_param.present? ? JSON.parse(variables_param) : {}
    when Hash, ActionController::Parameters then variables_param
    when nil then {}
    else raise ArgumentError, "Unexpected parameter topology: #{variables_param}"
    end
  end

  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end
end