require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  test "POST stores completed results and ignores client status and results" do
    results = [{ "position" => 1, "title" => "Ruby", "link" => "https://ruby-lang.org", "snippet" => "Ruby language" }]
    http = FakeHttp.new(response: http_response(success_payload(results).to_json))

    with_serpapi_client(SerpApiClient.new(api_key: "test", http: http)) do
      assert_difference("Search.count", 1) do
        post searches_url, params: { search: { query: "ruby", status: "failed", results: ["untrusted"] } }, as: :json
      end
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert_equal results, body["results"]
    assert_equal results, Search.find(body["id"]).results
    assert body["created_at"]
    assert body["updated_at"]
    assert_equal 1, http.requests.length
  end

  test "POST with invalid query returns 422 without contacting the provider or saving" do
    http = FakeHttp.new

    with_serpapi_client(SerpApiClient.new(api_key: "test", http: http)) do
      assert_no_difference("Search.count") do
        post searches_url, params: { search: { query: " " } }, as: :json
      end
    end

    assert_response :unprocessable_entity
    assert_equal ["Query can't be blank"], response.parsed_body["errors"]
    assert_empty http.requests
  end

  test "POST with missing parameters keeps the JSON 400 response" do
    assert_no_difference("Search.count") { post searches_url, params: {}, as: :json }

    assert_response :bad_request
    assert_kind_of Array, response.parsed_body["errors"]
  end

  test "POST with a non-hash search parameter returns JSON 400 without contacting the provider or saving" do
    http = FakeHttp.new

    with_serpapi_client(SerpApiClient.new(api_key: "test", http: http)) do
      assert_no_difference("Search.count") do
        post searches_url, params: { search: "ruby" }, as: :json
      end
    end

    assert_response :bad_request
    assert_equal ["param is missing or the value is empty or invalid: search"], response.parsed_body["errors"]
    assert_empty http.requests
  end

  test "POST with timeout saves a failed record and returns 504 with its ID" do
    assert_provider_failure(FakeHttp.new(error: Net::ReadTimeout.new("secret")), 504,
                            "Search provider timed out.")
  end

  test "POST with HTTP failure saves a failed record and returns 502 with its ID" do
    assert_provider_failure(FakeHttp.new(response: http_response("secret", code: "429")), 502,
                            "Search provider returned an HTTP error.")
  end

  test "POST with provider error saves a failed record and returns 502 with its ID" do
    payload = { "search_metadata" => { "status" => "Error" }, "error" => "secret" }
    assert_provider_failure(FakeHttp.new(response: http_response(payload.to_json)), 502,
                            "Search provider could not complete the search.")
  end

  test "POST with invalid response saves a failed record and returns 502 with its ID" do
    assert_provider_failure(FakeHttp.new(response: http_response("{}")), 502,
                            "Search provider returned an invalid response.")
  end

  test "POST without credentials saves a failed record and returns 503 without HTTP" do
    http = FakeHttp.new
    assert_provider_failure(http, 503, "Search provider is not configured.", api_key: "", expected_requests: 0)
  end

  test "POST with documented no matches completes with an empty JSON array" do
    payload = { "search_metadata" => { "status" => "Success" },
                "search_information" => { "organic_results_state" => "Fully empty" },
                "error" => "Google hasn't returned any results for this query." }
    http = FakeHttp.new(response: http_response(payload.to_json))
    with_serpapi_client(SerpApiClient.new(api_key: "test", http: http)) do
      post searches_url, params: { search: { query: "no matches" } }, as: :json
    end

    assert_response :created
    assert_equal "completed", response.parsed_body["status"]
    assert_equal [], Search.find(response.parsed_body["id"]).results
  end

  test "GET returns saved results and DELETE removes the record without a provider request" do
    search = Search.create!(query: "ruby", status: "completed", results: [{ "title" => "Ruby" }], created_at: 1.day.ago)
    newest = Search.create!(query: "rails")
    http = FakeHttp.new

    with_serpapi_client(SerpApiClient.new(api_key: "test", http: http)) do
      get searches_url, as: :json
      assert_response :ok
      assert_equal [newest.id, search.id], response.parsed_body.map { |item| item["id"] }
      assert_equal [{ "title" => "Ruby" }], response.parsed_body.last["results"]

      get search_url(search), as: :json
      assert_response :ok
      assert_equal search.results, response.parsed_body["results"]

      assert_difference("Search.count", -1) { delete search_url(search), as: :json }
      assert_response :no_content
      assert_empty response.body
      assert_empty http.requests
    end
  end

  test "unknown IDs keep the JSON 404 response" do
    get search_url(id: 0), as: :json
    assert_response :not_found
    assert_equal ["Record not found"], response.parsed_body["errors"]

    delete search_url(id: 0), as: :json
    assert_response :not_found
    assert_equal ["Record not found"], response.parsed_body["errors"]
  end

  private

  def assert_provider_failure(http, status, message, api_key: "test", expected_requests: 1)
    with_serpapi_client(SerpApiClient.new(api_key: api_key, http: http)) do
      assert_difference("Search.count", 1) do
        post searches_url, params: { search: { query: "ruby" } }, as: :json
      end
    end

    assert_response status
    assert_equal [message], response.parsed_body["errors"]
    search = Search.find(response.parsed_body.fetch("search_id"))
    assert_equal "failed", search.status
    assert_equal [], search.results

    get search_url(search), as: :json
    assert_response :ok
    assert_equal "failed", response.parsed_body["status"]
    assert_equal expected_requests, http.requests.length
  end
end
