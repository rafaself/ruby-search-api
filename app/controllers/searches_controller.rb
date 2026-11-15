class SearchesController < ApplicationController
  def index
    render json: Search.order(created_at: :desc)
  end

  def create
    search = Search.new(search_params)

    if search.save
      search.perform!
      render json: search, status: :created
    else
      render json: { errors: search.errors.full_messages }, status: :unprocessable_entity
    end
  rescue SerpApiClient::Error => error
    render json: { errors: [error.message], search_id: search.id }, status: error.http_status
  end

  def show
    render json: Search.find(params[:id])
  end

  def destroy
    Search.find(params[:id]).destroy
    head :no_content
  end

  private

  def search_params
    params.expect(search: [:query, :location, :hl])
  end
end
