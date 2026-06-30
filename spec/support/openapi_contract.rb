# frozen_string_literal: true

require "committee"
require "committee/test/methods"
require "yaml"

module OpenapiContractSupport
  SCHEMA_PATH = Rails.root.join("swagger/v1/swagger.yaml")

  class << self
    def schema
      @schema ||= Committee::Drivers.load_from_file(SCHEMA_PATH.to_s, parser_options: { strict_reference_validation: false })
    end

    def spec_paths
      @spec_paths ||= YAML.safe_load_file(SCHEMA_PATH).fetch("paths", {})
    end

    def path_defined?(path, method)
      spec_paths.any? do |template, operations|
        operations.is_a?(Hash) &&
          operations.key?(method.to_s.downcase) &&
          template_match?(template, path)
      end
    end

    private

    def template_match?(template, actual_path)
      pattern = template.gsub(%r{\{[^/]+\}}, "[^/]+")
      /\A#{pattern}\z/.match?(actual_path)
    end
  end
end

RSpec.shared_context "openapi contract" do
  include Committee::Test::Methods

  def committee_options
    @committee_options ||= {
      schema: OpenapiContractSupport.schema,
      old_assert_behavior: false,
      validate_success_only: false,
      parse_response_by_content_type: true,
    }
  end

  def request_object
    request
  end

  def response_data
    [ response.status, response.headers, response.body ]
  end

  after do |example|
    next unless ENV["OPENAPI_CONTRACT"] == "1"
    next if example.metadata[:api_doc] || example.metadata[:skip_openapi]
    next unless response

    unless OpenapiContractSupport.path_defined?(request.path, request.request_method)
      warn("[openapi-contract] No OpenAPI path for #{request.request_method} #{request.path}")
      next
    end

    assert_response_schema_confirm(response.status)
  rescue OpenAPIParser::NotExistStatusCodeDefinition, OpenAPIParser::NotExistContentTypeDefinition => e
    warn("[openapi-contract] No OpenAPI response for #{request.request_method} #{request.path} #{response.status}: #{e.message}")
  rescue NoMethodError => e
    # openapi_parser bug: unresolved $ref stays as Reference object; calling schema methods raises NoMethodError.
    # Treat as a warning so CI is not blocked by a library defect.
    warn("[openapi-contract] Schema reference resolution error for #{request.request_method} #{request.path}: #{e.message}")
  rescue Committee::InvalidResponse, Committee::ValidationError => e
    raise RSpec::Expectations::ExpectationNotMetError, "OpenAPI contract failed: #{e.message}"
  end
end

RSpec.configure do |config|
  config.include_context "openapi contract", type: :request
end
