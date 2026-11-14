require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns the API health status" do
    get health_url, as: :json

    assert_response :ok
    assert_equal({ "status" => "ok" }, response.parsed_body)
  end
end
