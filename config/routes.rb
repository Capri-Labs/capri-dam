Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'

  use_doorkeeper
  devise_for :users, controllers: { sessions: 'users/sessions' }

  # Authentication-based Root Logic
  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end

  get '/dashboard', to: 'dashboard#index'
  get "up" => "rails/health#show", as: :rails_health_check

  # --- API Namespace (Consolidated) ---
  namespace :api do
    namespace :v1 do
      get 'search', to: 'assets#search'
      resources :folders, only: [:show, :create]
      resources :assets, only: [:show, :update, :create]
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
  end

  # --- Workflows ---
  scope module: 'workflows' do
    resources :workflows do
      member do
        patch :toggle_status
      end
      # Nested steps if you want to manage them independently later
      resources :workflow_steps, only: [:index, :create, :update, :destroy]
    end
  end
end