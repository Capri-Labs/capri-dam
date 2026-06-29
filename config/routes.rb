require "sidekiq/web"
require "sidekiq/throttled/web" # Adds the "Throttled" tab to your Sidekiq UI

Rails.application.routes.draw do
  # ==========================================
  # 1. MOUNTS, ENGINES & DEV TOOLS
  # ==========================================
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => "/admin/queues"

    # Coverband runtime/E2E coverage dashboard (development & production only).
    if defined?(Coverband)
      mount Coverband::Reporters::Web.new, at: "/admin/coverband"
    end
  end

  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end

  # ==========================================
  # UNIFIED API DOCUMENTATION PORTAL
  # ==========================================
  # Primary docs URLs
  get "/api/rest",    to: "api/docs#rest"
  get "/api/graphql", to: "api/docs#graphql"

  # Legacy redirects — keep old bookmarks working
  get "/docs/graphql",   to: redirect("/api/graphql")
  get "/api_docs/index", to: redirect("/api/rest")
  get "/developers/api", to: redirect("/api/rest")

  # Rswag engines (still needed to serve /api-docs/v1/swagger.yaml)
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  # The actual data engine
  post "/graphql", to: "graphql#execute"

  # ==========================================
  # 2. AUTHENTICATION & ROOT LOGIC
  # ==========================================
  use_doorkeeper
  devise_for :users, controllers: {
    sessions:            "users/sessions",
    omniauth_callbacks:  "users/omniauth_callbacks",
  }

  devise_scope :user do
    post "users/force_password_update", to: "users/sessions#force_password_update"
  end

  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end

  # ==========================================
  # 3. FRONTEND UI ROUTES (HTML Shells)
  # ==========================================
  get "/dashboard", to: "dashboard#index"
  get "/reports", to: "admin/reports#index"
  get "/bin", to: "dashboard#bin"
  get "/folders", to: "dashboard#folders"
  get "/assets", to: "dashboard#assets"     # /assets?id=UUID deep-link
  get "/duplicates", to: "dashboard#duplicates"
  get "/search", to: "dashboard#search"
  get "up" => "rails/health#show", as: :rails_health_check

  # ── User self-service profile ──────────────────────────────────────────────
  resource :profile, only: [ :show, :update ], controller: "profile" do
    patch :password,     to: "profile#update_password"
    patch :preferences,  to: "profile#update_preferences"
    get   :activity,     to: "profile#activity"

    resources :personal_access_tokens, only: [ :index, :create, :destroy ],
              controller: "profile/personal_access_tokens"
  end

  # ── Impersonation engine ───────────────────────────────────────────────────
  namespace :impersonation do
    post   "start/:user_id", to: "sessions#create",  as: :start
    delete "stop",           to: "sessions#destroy", as: :stop
  end

  resources :collections, only: [ :index ]
  # Catch-all: serves the same React SPA shell for any /collections/* deep-link.
  # React Router (BrowserRouter basename="/collections") handles client-side routing.
  get "/collections/*path", to: "collections#index", as: :collection_workspace

  # Workflows UI
  get "/workflows", to: "workflows#index"
  get "workflows/dashboard", to: "workflows#dashboard"
  resources :workflows do
    member do
      patch :toggle_status
    end
    resources :workflow_steps, only: [ :index, :create, :update, :destroy ]
  end

  # AI UI — all actions require Devise session; agents/tasks/playground/provenance/style_model_hub are admin-only
  namespace :ai do
    get "copilot",                to: "ui#copilot"
    get "agents",                 to: "ui#agents"
    get "tasks",                  to: "ui#tasks"
    get "batch",                  to: redirect("/ai/tasks") # legacy alias
    get "lab/playground",         to: "ui#playground"
    get "governance/provenance",  to: "ui#provenance"
    get "governance",             to: redirect("/ai/governance/provenance") # hub redirect
    get "models/hub",             to: "ui#style_model_hub"
    get "models",                 to: redirect("/ai/models/hub") # short alias
  end

  # ==========================================
  # 4. SYSTEM SETTINGS
  # ==========================================
  resource :settings, only: [ :show, :update ], controller: "settings" do
    collection do
      patch :update_storage
      post :test_connection
      get :system, to: "settings#show", as: :system
    end
  end

  # ==========================================
  # 4b. TOOLS (HTML pages)
  # ==========================================
  namespace :tools do
    resources :metadata_schemas, only: [ :index ]
    resources :metadata_exports, only: [ :index ]
    resources :metadata_imports, only: [ :index ]
    resources :asset_configurations, only: [ :index ]
  end

  # ==========================================
  # 5. CORE API (v1)
  # ==========================================
  # Route to serve local storage files during development
  get "/api/v1/assets/local/:uuid", to: "api/v1/assets#serve_local", as: :serve_local_asset

  namespace :api do
    namespace :v1 do
      # Global Search & AI
      get "search", to: "search#index"
      post "copilot/search", to: "copilots#search"

      # AI Lab (Prompt Playground) — routes into Api::V1::Ai::LabController
      get  "ai/lab/models", to: "ai/lab#models", as: :ai_lab_models
      post "ai/lab/chat",   to: "ai/lab#chat",   as: :ai_lab_chat

      # Agent Workflows
      resources :agent_workflows, only: %i[index show create update destroy] do
        member do
          patch :toggle
          post  :trigger
          get   :executions
          post  :executions, to: "agent_workflows#log_execution", as: :log_execution
        end
      end

      # AI Batch Tasks (on-demand batch AI runs — /ai/tasks screen)
      resources :ai_batch_jobs, only: %i[index show create] do
        collection do
          get :task_types
        end
        member do
          post :cancel
          post :progress
        end
      end

      # C2PA / Content Provenance
      resource  :c2pa_configuration,      only: %i[show update]
      resources :asset_provenance_records, only: %i[index show] do
        collection do
          get  :stats
          post :bulk_upsert
        end
      end

      # Style & Model Hub — model configs + style presets
      resources :ai_model_configs, only: %i[index show create update destroy] do
        collection do
          get :capabilities
        end
        member do
          post :health_check
          post :set_default
          post :health_callback
        end
      end

      resources :style_presets, only: %i[index show create update destroy] do
        member do
          post :sync
          post :set_default
        end
      end

      # Dynamic CDN Configuration Routes
      get "cdn_configurations", to: "cdn_configurations#index"
      put "cdn_configurations", to: "cdn_configurations#update"

      # Recycle Bin — full CRUD with stats, bulk operations, retention policy, AI
      scope "bin" do
        get    "/",               to: "bin#index",                  as: :bin
        get    "stats",           to: "bin#stats",                  as: :bin_stats
        post   "bulk_restore",    to: "bin#bulk_restore",           as: :bin_bulk_restore
        delete "bulk_destroy",    to: "bin#bulk_destroy",           as: :bin_bulk_destroy
        delete "empty",           to: "bin#empty",                  as: :bin_empty
        get    "retention_policy", to: "bin#retention_policy",      as: :bin_retention_policy
        put    "retention_policy", to: "bin#update_retention_policy"
        post   "trigger_purge",   to: "bin#trigger_purge",          as: :bin_trigger_purge
        get    "purge_status",    to: "bin#purge_status",           as: :bin_purge_status
        # AI-powered suggestions (stub — will be powered by AI gateway)
        get    "ai/smart_suggestions", to: "bin#ai_smart_suggestions",  as: :bin_ai_smart_suggestions
        get    "ai/cleanup_report",    to: "bin#ai_cleanup_report",     as: :bin_ai_cleanup_report
      end

      # Edge Operations
      post "edge_operations/sync", to: "edge_operations#sync"
      post "edge_operations/purge", to: "edge_operations#purge"

      #  THE FIXED ASSETS BLOCK
      resources :assets do
        collection do
          post :check_hashes # Now correctly responds to POST /api/v1/assets/check_hashes
        end
        member do
          post :restore
          post :process_image
          delete :permanent, to: "assets#permanent_delete"
          get :workflow_history
          get :watermarked

          # Versioning Endpoints
          get :versions
          get :audit_trail
          post "versions/:version_id/restore", to: "assets#restore_version", as: :restore_version

          # Schema-driven metadata update
          patch :metadata, to: "assets#update_metadata"
        end
        # AI Embedding specific to this asset
        resource :embedding, only: [ :update ], controller: "asset_embeddings"
      end

      # Folders
      resources :folders, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :restore
          delete :permanent, to: "folders#permanent_delete"
          # Metadata schema management
          get    :schema,        to: "folders#schema"
          post   :apply_schema,  to: "folders#apply_schema"
          delete :remove_schema, to: "folders#remove_schema"
          # Profile assignments (info panel)
          get    :profiles,      to: "folders#profiles"
          # Access-control policies
          get    :policies,                to: "folders#folder_policies"
          post   :policies,                to: "folders#upsert_folder_policy"
          delete "policies/:group_id",     to: "folders#remove_folder_policy", as: :folder_policy
        end
      end

      # Collections
      resources :collections, param: :slug do
        collection do
          delete :bulk_delete
          patch :bulk_update
          post :simulate_rule
        end
        member do
          get :cluster_map
          post :rule, to: "collections#configure_rule"
          post "purge_cdn", to: "collections#purge_cdn"

          # Asset Join Table Operations
          post "assets", to: "collections#add_asset"
          post "assets/:asset_id", to: "collections#add_asset"
          delete "assets/:asset_id", to: "collections#remove_asset"
          patch "assets/:asset_id/pin", to: "collections#toggle_pin"
        end
      end

      # Data Health — TDM & Storage Health dashboard API
      resources :data_health, only: [] do
        collection do
          get  :overview
          get  :connectors
          post :remediate
        end
      end

      # Connectors & Ingestion
      resources :system_connectors, only: [ :index, :create, :update ] do
        collection do
          post :test_connection
          post :pre_flight_analysis
        end
        member do
          post :start_migration
        end
      end
      post "webhooks/connectors/:connector_id/receive", to: "webhooks#receive"

      resources :ingestion_items, only: [ :show, :update, :index ]
      resources :ingestion_batches, only: [ :create, :index, :show, :destroy ] do
        collection do
          get :stats
        end
        member do
          post :commit
          post :abort
          get  :report
        end
      end

      # Workflows API
      get  "workflows/dashboard",   to: "workflow_tasks#dashboard"
      post "workflows/bulk_stop",   to: "workflow_instances#bulk_stop"
      post "workflows/bulk_reassign", to: "workflow_instances#bulk_reassign"

      resources :workflow_tasks, only: [] do
        post :submit, on: :member
      end

      resources :workflow_instances, only: %i[index show destroy] do
        member do
          post :force_cancel
        end
      end

      # Notifications
      resource :ai_configuration, only: [ :show, :update ]
      resource :upload_restrictions, only: [ :show, :update ]
      resource :collection_settings, only: [ :show, :update ]

      # Duplicate Manager
      resource :duplicate_manager_settings, only: [ :show, :update ] do
        collection do
          get  :scan_status
          post :trigger_scan
        end
      end
      resources :duplicate_groups, only: [ :index, :show ] do
        collection do
          get  :stats
          patch :bulk_resolve
        end
        member do
          patch :resolve
          patch :dismiss
        end
      end

      # Image Profiles (asset upload processing configuration)
      resources :image_profiles, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :apply_to_folder
          delete :remove_from_folder
          get :folders
        end
      end

      # Video Profiles (video transcoding configuration)
      resources :video_profiles, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post   :copy
          post   :apply_to_folder
          delete :remove_from_folder
          get    :folders
        end
      end
      resources :notifications, only: [ :index ] do
        collection do
          patch :mark_all_read
        end
        member do
          patch :mark_read
        end
      end

      # Metadata Schemas
      resources :metadata_schemas, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post  :duplicate
          post  :apply_to_folder
          delete :remove_from_folder
          get :folders
        end
      end

      # User Groups (read-only search; write operations live in /admin/user_groups)
      resources :user_groups, only: [ :index ]

      # Metadata Export (async CSV export of asset metadata)
      resources :metadata_exports, only: [ :index, :show, :create, :destroy ] do
        collection do
          get :properties
        end
        member do
          get :download
        end
      end

      # Metadata Import (async CSV import / bulk metadata update)
      resources :metadata_imports, only: [ :index, :show, :create, :destroy ] do
        collection do
          get :template
        end
        member do
          get :download
        end
      end
    end
  end
  # ==========================================
  # 6. ADMIN & SYSTEM OPERATIONS
  # ==========================================
  namespace :admin do
    # System Status & Configs
    get "system_status", to: "system_status#index"
    post "system_status/update_smtp", to: "system_status#update_smtp"
    post "system_status/test_email", to: "system_status#test_email"
    post "system_status/restart_server", to: "system_status#restart_server"

    get "system_configurations/logging", to: "system_configurations#logging_status"
    post "system_configurations/logging", to: "system_configurations#update_logging"

    # Migrations
    get "migrations/ingestion", to: "migrations#ingestion"
    get "migrations/connectors", to: "migrations#connectors"
    get "migrations/health", to: "migrations#health"

    # Users & Access Control
    resources :system_accounts, only: [ :index, :show, :new, :create, :destroy ]

    resources :user_groups, except: [ :new, :edit ] do
      member do
        # Legacy — kept for backward-compat; prefer add_member/remove_member
        post   :add_user,    to: "user_groups#add_member"
        delete :remove_user, to: "user_groups#remove_member"
        # Members (users)
        post   :add_member
        delete :remove_member
        # Sub-group (group-in-group) membership
        post   :add_group_member
        delete :remove_group_member
      end
    end

    resources :users, only: [ :index, :show, :create, :update, :destroy ] do
      member do
        post   :toggle_status
        post   :change_password
        get    :groups
        post   :add_group
        delete "remove_group/:group_id", to: "users#remove_group", as: :remove_group
        get    :impersonators
        post   "impersonators",                   to: "users#add_impersonator",     as: :add_impersonator
        delete "impersonators/:impersonator_id",  to: "users#remove_impersonator",  as: :remove_impersonator
        post   :start_impersonation
        get    :preferences
        patch  :preferences,                      to: "users#update_preferences"
      end
    end

    resources :folders, only: [] do
      resources :folder_policies, only: [ :index, :create, :destroy ], param: :group_id
    end

    # Communications
    resources :email_templates, except: [ :new, :edit ]
    resources :email_deliveries, only: [ :index ] do
      member do
        post :retry
      end
    end

    # Reporting
    resources :reports, only: [ :index, :show ] do
      collection do
        get :analytics   # GET /admin/reports/analytics?range=last_30_days
      end
      member do
        post :generate
      end
    end

    resources :report_snapshots, only: [ :index ] do
      get :download, on: :member
    end
  end
end
