class SearchesController < ApplicationController
  def index
    render json: Search.order(created_at: :desc)
  end

  def create
    search = Search.new(search_params)

    if search.save
      render json: search, status: :created
    else
      render json: { errors: search.errors.full_messages }, status: :unprocessable_entity
    end
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
    params.require(:search).permit(:query)
  end
end
