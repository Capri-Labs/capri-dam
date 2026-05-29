# frozen_string_literal: true

require 'rails_helper'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  config.swagger_docs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Headless DAM API',
        version: 'v1',
        description: <<~DESC,
          An enterprise-grade, cloud-agnostic Digital Asset Management system designed for zero noise operations and high-scale automation.

          ### Core Capabilities
          * **Asset Lifecycle Management**: Upload, process, and retrieve media assets asynchronously.
          * **Workflow Automation**: Configurable event-driven state machines for asset approval and metadata pipelines.
          * **Operational Governance**: Granular role-based access control (RBAC), hierarchical user groups, and comprehensive administrative oversight.
          * **Cloud-Agnostic Storage**: Plug-and-play architecture supporting AWS S3, Cloudflare R2, Google Cloud Storage, and local environments.

          ### Authentication
          This API utilizes OAuth 2.0 for secure access. System-to-system integrations should utilize the Client Credentials grant type.
          
          1. Call `POST /oauth/token` with your `client_id` and `client_secret`.
          2. Click the **Authorize** button on this page and enter the resulting token.
        DESC
        termsOfService: 'https://github.com/apelluru/headless-dam',
        contact: {
          name: 'Ashok Pelluru | Operational Governance & Architecture',
          url: 'https://github.com/apelluru/headless-dam'
        },
        license: {
          name: 'MIT License',
          url: 'https://opensource.org/licenses/MIT'
        }
      },
      paths: {},
      servers: [
        {
          url: 'http://localhost:3000',
          description: 'Local Development Server'
        },
        {
          url: 'https://api.yourdam.com',
          description: 'Production Environment'
        }
      ],
      components: {
        securitySchemes: {
          Bearer: {
            type: :http,
            scheme: :bearer,
            description: 'Enter your OAuth 2.0 Bearer token to authenticate requests.'
          }
        }
      }
    }
  }

  config.openapi_format = :yaml
end