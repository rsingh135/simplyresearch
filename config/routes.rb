Rails.application.routes.draw do
  devise_for :admins,
             controllers: {
               omniauth_callbacks: "admins/omniauth_callbacks"
             }

  # Google Cross-Account Protection (RISC) endpoint
  # See: https://developers.google.com/identity/protocols/risc
  post "/risc/events", to: "risc_events#create"

  resources :users

  # Update the documents resource to include the new route
  resources :documents do
    member do
      post :generate_presentation
      get :status # JSON endpoint for AJAX status polling
    end
  end

  get "home/about"
  get "home/services"

  # Monitoring Dashboard (Protected for Admins only)
  authenticate :admin do
    mount GoodJob::Engine => "good_job"
  end

  root "home#index"
  get "up" => "rails/health#show", :as => :rails_health_check
end
