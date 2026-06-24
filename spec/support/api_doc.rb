# ---------------------------------------------------------------------------
# rswag API-documentation specs
# ---------------------------------------------------------------------------
# The `spec/requests/**` files that `require 'swagger_helper'` and call
# `run_test!` exist primarily to GENERATE the OpenAPI/Swagger docs
# (`bundle exec rails rswag:specs:swaggerize`). They are scaffolds: most do not
# define `let(:Authorization)` or their path params.
#
# Behaviour:
#   • DEFAULT run  — `:api_doc` examples are EXCLUDED (suite stays green).
#   • `RUN_API_DOCS=1` — examples are included; auth + path-param defaults are
#     injected automatically so `make test-api-docs` runs without NoMethodError /
#     missing-param ArgumentError.
#
RSpec.configure do |config|
  # 1. Auto-tag every rswag example (they carry `:response` metadata).
  config.define_derived_metadata do |metadata|
    metadata[:api_doc] = true if metadata[:response].is_a?(Hash)
  end

  # 2. Exclude from the default run unless explicitly opted in.
  config.filter_run_excluding(api_doc: true) unless ENV['RUN_API_DOCS'] == '1'

  # 3. Sign in as an admin and provide default values for EVERY path/query param
  #    rswag may try to call — so no ArgumentError or NoMethodError is raised.
  config.before(:each, :api_doc) do
    @api_doc_user = FactoryBot.create(:user, admin: true)
    sign_in @api_doc_user
  end

  param_defaults = Module.new do
    # ── Bearer auth ─────────────────────────────────────────────────────────
    # rswag resolves the `Bearer` scheme by calling `Authorization` on the
    # example group. Return a placeholder; the real auth is the Devise session.
    define_method(:Authorization) { 'Bearer rspec-api-doc-token' }

    # ── Common path parameters ───────────────────────────────────────────────
    define_method(:id)            { 0 }
    define_method(:folder_id)     { 0 }
    define_method(:asset_id)      { 0 }
    define_method(:version_id)    { 0 }
    define_method(:connector_id)  { 0 }
    define_method(:slug)          { 'placeholder-slug' }
    define_method(:uuid)          { '00000000-0000-0000-0000-000000000000' }

    # ── Common body / query / form params ────────────────────────────────────
    define_method(:payload)       { {} }
    define_method(:q)             { nil }
    define_method(:mode)          { nil }
    define_method(:schema_id)     { nil }
    define_method(:type)          { nil }
    define_method(:file)          { nil }
    define_method(:reject)        { 'false' }
    define_method(:grant_type)    { 'client_credentials' }
    define_method(:client_id)     { 'placeholder-client-id' }
    define_method(:client_secret) { 'placeholder-client-secret' }
  end

  config.include param_defaults, :api_doc
end

