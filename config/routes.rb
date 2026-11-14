Rails.application.routes.draw do
  get "health", to: "health#show"

  resources :searches, only: %i[index create show destroy]
end
