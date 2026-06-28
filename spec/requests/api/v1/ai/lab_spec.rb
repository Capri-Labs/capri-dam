# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::Ai::Lab", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  # ===========================================================================
  # GET /api/v1/ai/lab/models
  # ===========================================================================
  path "/api/v1/ai/lab/models" do
    get "List available AI models for the active provider" do
      tags        "AI Lab"
      produces    "application/json"
      security    [ Bearer: [] ]
      description <<~DESC
        Returns the active provider from `AiConfiguration`, the default generation
        model, and the model list for that provider. Used by the Prompt Playground
        to populate the model selector without hard-coding provider info in the
        frontend.
      DESC

      response "200", "Model list returned" do
        schema type: :object,
               required: %w[active_provider default_model models],
               properties: {
                 active_provider: { type: :string, example: "openai" },
                 default_model:   { type: :string, example: "gpt-4o" },
                 models:          { type: :array, items: { type: :string } },
                 all_providers:   { type: :object },
               }
        run_test!
      end

      response "401", "Unauthenticated" do
        schema type: :object, properties: { error: { type: :string } }
        before { sign_out user }
        run_test!
      end
    end
  end

  # ===========================================================================
  # POST /api/v1/ai/lab/chat
  # ===========================================================================
  path "/api/v1/ai/lab/chat" do
    post "Send a prompt conversation to the AI Gateway" do
      tags        "AI Lab"
      consumes    "application/json"
      produces    "application/json"
      security    [ Bearer: [] ]
      description <<~DESC
        Proxies a chat-completion request to the configured AI Gateway
        (`AI_GATEWAY_URL`). The request body mirrors the OpenAI chat completions
        format. Returns the raw gateway response including `choices` and `usage`.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[messages],
        properties: {
          messages: {
            type: :array,
            items: {
              type:       :object,
              required:   %w[role content],
              properties: {
                role:    { type: :string, enum: %w[system user assistant] },
                content: { type: :string },
              },
            },
          },
          model:       { type: :string, example: "gpt-4o-mini" },
          temperature: { type: :number, example: 0.7 },
          max_tokens:  { type: :integer, example: 1024 },
        },
      }

      response "200", "Completion returned by AI Gateway" do
        schema type: :object,
               properties: {
                 choices: {
                   type: :array,
                   items: {
                     type:       :object,
                     properties: {
                       message: {
                         type:       :object,
                         properties: {
                           role:    { type: :string },
                           content: { type: :string },
                         },
                       },
                     },
                   },
                 },
                 usage: {
                   type:       :object,
                   properties: {
                     prompt_tokens:     { type: :integer },
                     completion_tokens: { type: :integer },
                     total_tokens:      { type: :integer },
                   },
                 },
                 model: { type: :string },
               }

        # Stub the Faraday call so the spec doesn't require a running gateway
        before do
          stub_gateway_chat_response
        end

        let(:payload) do
          {
            messages: [
              { role: "system",  content: "You are a helpful assistant." },
              { role: "user",    content: "What is a DAM?" },
            ],
            model:       "gpt-4o-mini",
            temperature: 0.5,
            max_tokens:  256,
          }
        end

        run_test!
      end

      response "422", "Messages parameter missing" do
        let(:payload) { {} }
        run_test!
      end

      response "401", "Unauthenticated" do
        before { sign_out user }
        let(:payload) { { messages: [ { role: "user", content: "test" } ] } }
        run_test!
      end

      response "503", "AI Gateway unavailable" do
        schema type: :object, properties: { error: { type: :string } }
        before { stub_gateway_connection_failed }
        let(:payload) { { messages: [ { role: "user", content: "hi" } ] } }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  private

  def stub_gateway_chat_response
    fake_conn = instance_double(Faraday::Connection)
    fake_resp = instance_double(Faraday::Response,
      success?: true,
      status:   200,
      body: {
        "choices" => [ { "message" => { "role" => "assistant", "content" => "DAM = Digital Asset Management." } } ],
        "usage"   => { "prompt_tokens" => 20, "completion_tokens" => 10, "total_tokens" => 30 },
        "model"   => "gpt-4o-mini",
      })
    allow(Faraday).to receive(:new).and_return(fake_conn)
    allow(fake_conn).to receive(:post).and_yield(instance_double(Faraday::Request, body: nil)).and_return(fake_resp)
  end

  def stub_gateway_connection_failed
    allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
  end
end
