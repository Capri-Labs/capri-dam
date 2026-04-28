# frozen_string_literal: true

require 'rails_helper'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  config.swagger_docs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Headless DAM API V1',
        version: 'v1',
        description: 'Secure, Cloud-Agnostic Asset Management API'
      },
      paths: {},
      components: {
        securitySchemes: {
          bearer_auth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: :JWT
          }
        }
      },
      servers: [
        {
          url: 'http://localhost:3000',
          description: 'Local Development Server'
        }
      ]
    }
  }

  config.openapi_format = :yaml
end