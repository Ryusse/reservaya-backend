Rails.application.routes.draw do
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
  get "up" => "rails/health#show", as: :rails_health_check

  post "register", to: "registrations#create"
  resource :session, only: [:show, :create, :destroy]

  resources :users
  resources :spaces
  resources :reservations, only: [:index, :show, :create, :update] do
    member do
      patch :cancel
    end
  end
  resource :dashboard, only: [:show], controller: :dashboard

  namespace :dashboard do
    resource :occupancy, only: [:show]
  end
end
