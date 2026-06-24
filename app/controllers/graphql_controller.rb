# GraphQL execution endpoint for the Headless DAM platform.
#
# All GraphQL operations (queries and mutations) are sent as HTTP POST requests
# to +POST /graphql+.  This controller resolves the incoming request, wires up
# the execution context, and delegates to {HeadlessDamSchema}.
#
# == Authentication
#
# Every operation is authenticated via {ApplicationController#authenticate_hybrid!}
# (Devise session **or** Doorkeeper OAuth token) *except* schema introspection
# requests in the development environment.  This keeps the GraphiQL IDE usable
# locally while ensuring the production API is fully locked.
#
# == Security limits
#
# To defend against abusive queries the schema is executed with:
# * +max_depth: 6+ — prevents deeply nested queries.
# * +max_complexity: 200+ — limits the aggregate resolver cost.
#
# Both limits are lifted for introspection queries so that tooling (GraphiQL,
# Insomnia, etc.) can still retrieve the full SDL in development.
#
# == Error handling
#
# Unhandled exceptions are re-raised in non-development environments so that
# the standard Rails error reporter takes over.  In development, a detailed
# error payload (message + backtrace) is returned as JSON for fast debugging.
#
# @see HeadlessDamSchema
# @see Types::QueryType
# @see Types::MutationType
class GraphqlController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Skip auth for schema introspection in development only.
  before_action :authenticate_hybrid!, unless: :introspection_query?

  # Executes a GraphQL operation and renders the result as JSON.
  #
  # Accepts the standard GraphQL-over-HTTP request shape:
  # * +query+         — the GraphQL document string
  # * +variables+     — input variables (JSON string, hash, or nil)
  # * +operationName+ — which operation to run when the document has multiple
  #
  # @return [void] renders JSON with the GraphQL result (or error payload)
  def execute
    variables      = prepare_variables(params[:variables])
    query          = params[:query]
    operation_name = params[:operationName]

    context = {
      current_user: current_user,
      session_id:   session.id
    }

    is_introspection = introspection_query?

    result = HeadlessDamSchema.execute(
      query,
      variables:      variables,
      context:        context,
      operation_name: operation_name,
      max_depth:      is_introspection ? nil : 6,
      max_complexity: is_introspection ? nil : 200
    )

    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  private

  # Returns +true+ when the current request is a schema introspection in development.
  #
  # In production this always returns +false+, ensuring full authentication is
  # enforced for every request.
  #
  # @return [Boolean]
  def introspection_query?
    Rails.env.development? && params[:operationName] == 'IntrospectionQuery'
  end

  # Normalises the +variables+ parameter into a plain Ruby Hash.
  #
  # GraphQL clients may send variables as a JSON string, an ActionController
  # Parameters object, a Hash, or simply omit them.  This method handles all
  # four cases.
  #
  # @param variables_param [String, Hash, ActionController::Parameters, nil]
  # @return [Hash]
  # @raise [ArgumentError] for any other type
  def prepare_variables(variables_param)
    case variables_param
    when String                             then variables_param.present? ? JSON.parse(variables_param) : {}
    when Hash, ActionController::Parameters then variables_param
    when nil                                then {}
    else raise ArgumentError, "Unexpected parameter topology: #{variables_param}"
    end
  end

  # Returns a developer-friendly JSON error payload including the backtrace.
  # Only called in the development environment.
  #
  # @param e [Exception]
  # @return [void]
  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end
end