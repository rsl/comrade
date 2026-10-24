Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # show lands with 3a's conversation page; the route exists because the
  # resource's address (Location header) is already part of the 2a contract.
  root 'conversations#index'

  resources :conversations, only: %i[index create show destroy] do
    collection do
      get :archived
    end
    member do
      patch :archive
      patch :unarchive
    end
    resources :messages, only: [:create]
  end

  # Identity: one door, singular resource. new marks the panel seen,
  # create enlists or claims, destroy steps out to the commune.
  resource :enlistment, only: %i[new create destroy]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
