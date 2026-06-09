require 'sidekiq/web'
require 'sidekiq/throttled/web' # Adds the "Throttled" tab to your Sidekiq UI

Rails.application.routes.draw do

  # The exact routing constraint depends on authentication system.
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => '/admin/queues'
  end

  get '/docs/graphql', to: redirect('/graphql-docs/index.html')

  # The actual data engine
  post "/graphql", to: "graphql#execute"

  # The Interactive Sandbox for your browser (Accepts GET)
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end

  get "api_docs/index"
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'

  use_doorkeeper
  devise_for :users, controllers: { sessions: 'users/sessions' }

  devise_scope :user do
    post 'users/force_password_update', to: 'users/sessions#force_password_update'
  end

  # Authentication-based Root Logic
  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end

  # The new 100% open-source UI for API documentation
  get '/developers/api', to: 'api_docs#index'

  get '/dashboard', to: 'dashboard#index'
  get '/reports', to: 'admin/reports#index'
  get '/bin', to: 'dashboard#bin'
  get '/folders', to: 'dashboard#folders'
  get '/duplicates', to: 'dashboard#duplicates'
  get '/search', to: 'dashboard#search'
  get "up" => "rails/health#show", as: :rails_health_check

  resources :collections, only: [:index]

  # --- API Namespace (Consolidated) ---
  namespace :api do
    namespace :v1 do
      get 'search', to: 'search#index'
      # The global bin endpoint
      get 'bin', to: 'assets#bin'
      # The entry point for the React Semantic Copilot UI
      post 'copilot/search', to: 'copilots#search'


      resources :folders, only: [:show, :create]
      resources :assets, only: [:show, :update, :create] do
        # Explicitly point to the asset_embeddings controller
        resource :embedding, only: [:update], controller: 'asset_embeddings'
      end

      resources :collections, param: :slug do
        # Batch/Bulk Operations
        collection do
          delete :bulk_delete
          patch :bulk_update
        end

        # Single Item & Member Operations
        member do
          post :rule, to: 'collections#configure_rule'
          post 'purge_cdn', to: 'collections#purge_cdn'

          # Asset Join Table Operations
          post 'assets', to: 'collections#add_asset'            # Add via URL payload or body
          post 'assets/:asset_id', to: 'collections#add_asset'  # Add specific asset
          delete 'assets/:asset_id', to: 'collections#remove_asset'
          patch 'assets/:asset_id/pin', to: 'collections#toggle_pin'
        end
      end

      resources :assets do
        member do
          post :restore
          delete :permanent, to: 'assets#permanent_delete'
          get :workflow_history
        end
      end

      resources :folders do
        member do
          post :restore
          delete :permanent, to: 'folders#permanent_delete'
        end
      end

    end
  end

  # --- Settings Resource (Consolidated) ---
  # Using 'resource' (singular) because there is only one set of settings per user/system
  resource :settings, only: [:show, :update], controller: 'settings' do
    collection do
      patch :update_storage
      post :test_connection # Now accessible as test_connection_settings_path

      # NEW: Renders SettingsIndex in System Mode via SettingsController#show
      get :system, to: 'settings#show', as: :system
    end
  end

  # --- System Operations & Observability API ---
  # Keeps the high-privilege metrics and SMTP updates isolated under an admin space
  namespace :admin do
    get 'system_status', to: 'system_status#index'
    post 'system_status/update_smtp', to: 'system_status#update_smtp'
    post 'system_status/test_email', to: 'system_status#test_email'
    post 'system_status/restart_server', to: 'system_status#restart_server'

    #Operational Logging Configuration Routes
    get 'system_configurations/logging', to: 'system_configurations#logging_status'
    post 'system_configurations/logging', to: 'system_configurations#update_logging'
  end

  # --- Admin Namespace ---
  namespace :admin do

    get 'migrations/ingestion', to: 'migrations#ingestion'
    get 'migrations/connectors', to: 'migrations#connectors'
    get 'migrations/health', to: 'migrations#health'

    resources :system_accounts, only: [:index, :show, :new, :create, :destroy]

    # Group & Membership Management
    resources :user_groups, except: [:new, :edit] do
      member do
        post :add_user
        delete :remove_user
      end
    end

    # User Directory & Identity Management
    resources :users, only: [:index, :create, :update] do
      member do
        post :toggle_status
      end
    end

    # Folder Access Control Lists (Nested under folders)
    resources :folders, only: [] do
      resources :folder_policies, only: [:index, :create, :destroy], param: :group_id
    end

    # Communication Engine
    resources :email_templates, except: [:new, :edit]

    resources :email_deliveries, only: [:index] do
      member do
        post :retry # Endpoint to manually retry a failed email
      end
    end

    # Routing for Report Definitions
    resources :reports, only: [:index, :show] do
      post :generate, on: :member
    end

    # Routing for Snapshot downloads
    resources :report_snapshots, only: [:index] do
      get :download, on: :member
    end
  end

  namespace :ai do
    get 'copilot', to: 'ui#copilot'
    get 'agents',  to: 'ui#agents'
    get 'batch',   to: 'ui#batch'
  end

  # 1. THE FRONTEND ROUTE (Serves the HTML Shell)
  # --- Workflows ---
  get '/workflows', to: 'workflows#index'
  get 'workflows/dashboard', to: 'workflows#dashboard'
  resources :workflows do
    member do
      patch :toggle_status
    end
    # Nested steps if you want to manage them independently later
    resources :workflow_steps, only: [:index, :create, :update, :destroy]
  end

  resources :workflow_tasks, only: [] do
    post :submit, on: :member
  end

  # 2. THE API ROUTES (Serves the JSON Data)
  namespace :api do
    namespace :v1 do

      resource :ai_configuration, only: [:show, :update]

      resources :system_connectors, only: [:index, :create, :update] do
        collection do
          post :test_connection
          post :pre_flight_analysis # POST /api/v1/system_connectors/:id/pre_flight_analysis
        end
      end

      post 'webhooks/connectors/:connector_id/receive', to: 'webhooks#receive'

      # UI Route for the Ingestion Dashboard
      resources :ingestion_items, only: [:show, :update]
      resources :ingestion_batches, only: [:create, :index]

      # Add this line to map the dashboard fetch request to your specific controller
      get 'workflows/dashboard', to: 'workflow_tasks#dashboard'

      resources :workflow_tasks, only: [] do
        post :submit, on: :member
      end

      # ... notifications routes ...
      resources :notifications, only: [:index] do
        collection do
          patch :mark_all_read
        end
        member do
          patch :mark_read
        end
      end

    end
  end

end