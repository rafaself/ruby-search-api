class ApplicationController < ActionController::API
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_bad_request(error)
    render json: { errors: [error.message] }, status: :bad_request
  end

  def render_not_found
    render json: { errors: ["Record not found"] }, status: :not_found
  end
end
