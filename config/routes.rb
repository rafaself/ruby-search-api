Rails.application.routes.draw do
  get "health", to: "health#show"

  resources :searches, only: %i[index create show destroy]
  ## Equivalent to
  # get    "/searches",     to: "searches#index", as: :searches
  # post   "/searches",     to: "searches#create"
  # get    "/searches/:id", to: "searches#show", as: :search
  # delete "/searches/:id", to: "searches#destroy"
end
