Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :projects, only: %i[index new create show edit update destroy] do
    resources :tasks, only: %i[new create show destroy] do
      resources :agent_runs, only: [:create]
      post :unblock, on: :member
      post :pause, on: :member
      post :stop, on: :member
      post :abandon, on: :member
      post :guide, on: :member
      patch :update_status, on: :member
      get :heartbeat, on: :member
      delete :clear_completed, on: :collection
    end
    resources :audit_tasks, only: [:create]
  end

  # Defines the root path route ("/")
  root "projects#index"
end
