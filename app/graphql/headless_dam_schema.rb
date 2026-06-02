class HeadlessDamSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  rescue_from(StandardError) do |err, ctx, ast_node, path|
    GraphQL::ExecutionError.new("Internal server error: Operational noise suppressed.")
  end
end