module Api
  class DocsController < ApplicationController
    # Public documentation — no auth, no browser-version gate, no CSRF
    skip_before_action :verify_authenticity_token
    skip_before_action :set_current_context, raise: false
    before_action :allow_any_browser

    # GET /api/rest  — interactive Swagger UI
    def rest
      render layout: false, content_type: 'text/html'
    end

    # GET /api/graphql  — SpectaQL-generated GraphQL docs
    def graphql
      send_file Rails.root.join("public/graphql-docs/index.html"),
                type:        "text/html",
                disposition: "inline"
    end


    private

    def allow_any_browser
      # No-op: intentionally bypasses the allow_browser :modern guard
      # so API docs are accessible from all browsers and API clients.
    end
  end
end



