module Api
  module V1
    module Ai
      class TemplateSuggestionsController < ApplicationController
        before_action :authenticate_hybrid!

        def index
          render json: {
            suggestions: [
              {
                id: "subject-personalization",
                title: "Strengthen subject personalization",
                summary: "Include the recipient's first name or the triggering asset to improve open rates.",
                severity: "info",
              },
              {
                id: "cta-clarity",
                title: "Clarify the next action",
                summary: "Add a single prominent call-to-action so recipients know where to continue the workflow.",
                severity: "info",
              },
            ],
          }
        end
      end
    end
  end
end
