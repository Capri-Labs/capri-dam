Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  use_doorkeeper
  devise_for :users, controllers: {
    sessions: 'users/sessions'
  }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end

  # Optional: Keep the dashboard accessible at /dashboard
  get '/dashboard', to: 'dashboard#index'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  namespace :api do
    namespace :v1 do
      get 'search', to: 'assets#search'
      resources :assets, only: [:create]
    end
  end

  # This creates settings_path (for show) and update_settings_path
  resource :settings, only: [:show, :update], controller: 'settings'

  namespace :admin do
    # This creates admin_system_accounts_path, admin_system_account_path(id), etc.
    resources :system_accounts, only: [:index, :show, :new, :create, :destroy]
    # ... other admin routes ...
  end

  # This is for folders and assets
  namespace :api do
    namespace :v1 do
      # Add :create here
      resources :folders, only: [:show, :create]
      resources :assets, only: [:show, :update, :create]
    end
  end

  resource :settings, only: [:show, :update] do
    collection do
      patch :update_storage
    end
  end
end
