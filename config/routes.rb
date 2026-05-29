Rails.application.routes.draw do
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

  get "up" => "rails/health#show", as: :rails_health_check

  # --- API Namespace (Consolidated) ---
  namespace :api do
    namespace :v1 do
      get 'search', to: 'assets#search'
      # The global bin endpoint
      get 'bin', to: 'assets#bin'

      resources :folders, only: [:show, :create]
      resources :assets, only: [:show, :update, :create]

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
  end

  # --- Admin Namespace ---
  namespace :admin do
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

      # ... assets and folders routes ...
    end
  end

end