# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::AiConfiguration', type: :request do
  # ===========================================================================
  # SHOW — GET /api/v1/ai_configuration
  # ===========================================================================
  path '/api/v1/ai_configuration' do
    get 'Retrieve the current AI Gateway configuration' do
      tags 'CDN & Settings'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the singleton `AiConfiguration` record. This controls which
        provider and model the AI Gateway uses for text generation and embedding.
      DESC

      response '200', 'AI configuration returned' do
        schema type: :object,
               properties: {
                 id:                { type: :integer },
                 active_provider:   { type: :string, example: 'openai',
                                      description: 'openai | anthropic | local' },
                 generation_model:  { type: :string, example: 'gpt-4o' },
                 embedding_model:   { type: :string, example: 'text-embedding-ada-002' },
                 monthly_budget_usd: { type: :number, example: 200.00 },
                 system_prompt:     { type: :string, nullable: true },
                 fallback_to_local: { type: :boolean, example: false },
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    patch 'Update the AI Gateway configuration' do
      tags 'CDN & Settings'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Updates the singleton AI configuration. Changes take effect immediately
        for all subsequent AI Gateway calls. Set `fallback_to_local: true` to
        use a locally-hosted LLM when the primary provider is unavailable.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'ai_configuration' ],
        properties: {
          ai_configuration: {
            type: :object,
            properties: {
              active_provider:    { type: :string, example: 'openai' },
              generation_model:   { type: :string, example: 'gpt-4o' },
              embedding_model:    { type: :string, example: 'text-embedding-ada-002' },
              monthly_budget_usd: { type: :number, example: 500.00 },
              system_prompt:      { type: :string, nullable: true },
              fallback_to_local:  { type: :boolean },
            },
          },
        },
      }

      response '200', 'AI Gateway configuration synchronized' do
        schema type: :object,
               properties: {
                 message: { type: :string },
                 config:  { type: :object },
               }
        run_test!
      end

      response '422', 'Validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end
end
