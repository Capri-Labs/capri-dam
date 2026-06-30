# Root GraphQL schema for the Capri DAM platform.
#
# Wires together:
# * {Types::QueryType}    — all read operations
# * {Types::MutationType} — all write operations
#
# == Error handling
#
# All unhandled +StandardError+ exceptions are caught at the schema level and
# converted to a generic {GraphQL::ExecutionError} so that internal stack
# traces are never leaked to API consumers.  Development-mode details are
# surfaced separately by {GraphqlController#handle_error_in_development}.
#
# == Security limits (enforced by the controller)
#
# The controller applies +max_depth: 6+ and +max_complexity: 200+ for normal
# operations; see {GraphqlController#execute} for details.
#
# @see Types::QueryType
# @see Types::MutationType
# @see GraphqlController
class HeadlessDamSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # Suppress internal error details from API consumers.
  # In development the controller's own handler provides the full backtrace.
  rescue_from(StandardError) do |err, _ctx, _ast_node, _path|
    Rails.logger.error("[GraphQL] #{err.class}: #{err.message}\n#{err.backtrace&.first(5)&.join("\n")}")
    GraphQL::ExecutionError.new("Internal server error: Operational noise suppressed.")
  end
end
