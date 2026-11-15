require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  SERPAPI_URL_PATTERN = %r{\Ahttps://serpapi\.com/search\.json}

  test "POST stores completed results and ignores client status and results" do
    results = [{ "position" => 1, "title" => "Ruby", "link" => "https://ruby-lang.org", "snippet" => "Ruby language" }]
    location = "São Paulo, Brazil"
    hl = "pt"
    provider_request = stub_request(:get, SerpApiClient::ENDPOINT.to_s)
                      .with(query: {
                              "engine" => "google",
                              "q" => "ruby",
                              "api_key" => "test",
                              "async" => "false",
                              "location" => location,
                              "hl" => hl
                            }, headers: { "Accept" => "application/json" })
                      .to_return(status: 200, body: success_payload(results).to_json)

    with_serpapi_api_key("test") do
      assert_difference("Search.count", 1) do
        post searches_url,
             params: { search: { query: "ruby", location: location, hl: hl, status: "failed", results: ["untrusted"] } },
             as: :json
      end
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert_equal results, body["results"]
    search = Search.find(body["id"])
    assert_equal results, search.results
    assert_equal location, search.location
    assert_equal hl, search.hl
    assert body["created_at"]
    assert body["updated_at"]
    assert_requested provider_request, times: 1
  end

  test "POST with invalid query returns 422 without contacting the provider or saving" do
    assert_no_difference("Search.count") do
      post searches_url, params: { search: { query: " " } }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal ["Query can't be blank"], response.parsed_body["errors"]
    assert_not_requested :get, SERPAPI_URL_PATTERN
  end

  test "POST with missing parameters keeps the JSON 400 response" do
    assert_no_difference("Search.count") { post searches_url, params: {}, as: :json }

    assert_response :bad_request
    assert_kind_of Array, response.parsed_body["errors"]
  end

  test "POST with a non-hash search parameter returns JSON 400 without contacting the provider or saving" do
    assert_no_difference("Search.count") do
      post searches_url, params: { search: "ruby" }, as: :json
    end

    assert_response :bad_request
    assert_equal ["param is missing or the value is empty or invalid: search"], response.parsed_body["errors"]
    assert_not_requested :get, SERPAPI_URL_PATTERN
  end

  test "POST with timeout saves a failed record and returns 504 with its ID" do
    assert_provider_failure(stub_serpapi_request(error: Net::ReadTimeout.new("secret")), 504,
                            "Search provider timed out.")
  end

  test "POST with HTTP failure saves a failed record and returns 502 with its ID" do
    assert_provider_failure(stub_serpapi_request(body: "secret", status: 429), 502,
                            "Search provider returned an HTTP error.")
  end

  test "POST with provider error saves a failed record and returns 502 with its ID" do
    payload = { "search_metadata" => { "status" => "Error" }, "error" => "secret" }
    assert_provider_failure(stub_serpapi_request(body: payload.to_json), 502,
                            "Search provider could not complete the search.")
  end

  test "POST with invalid response saves a failed record and returns 502 with its ID" do
    assert_provider_failure(stub_serpapi_request(body: "{}"), 502,
                            "Search provider returned an invalid response.")
  end

  test "POST without credentials saves a failed record and returns 503 without HTTP" do
    assert_provider_failure(nil, 503, "Search provider is not configured.", api_key: "", expected_requests: 0)
  end

  test "POST with documented no matches completes with an empty JSON array" do
    payload = { "search_metadata" => { "status" => "Success" },
                "search_information" => { "organic_results_state" => "Fully empty" },
                "error" => "Google hasn't returned any results for this query." }
    provider_request = stub_serpapi_request(body: payload.to_json)
    with_serpapi_api_key("test") do
      post searches_url, params: { search: { query: "no matches" } }, as: :json
    end

    assert_response :created
    assert_equal "completed", response.parsed_body["status"]
    assert_equal [], Search.find(response.parsed_body["id"]).results
    assert_requested provider_request, times: 1
  end

  test "GET returns saved results and DELETE removes the record without a provider request" do
    search = Search.create!(query: "ruby", status: "completed", results: [{ "title" => "Ruby" }], created_at: 1.day.ago)
    newest = Search.create!(query: "rails")

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
    assert_not_requested :get, SERPAPI_URL_PATTERN
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

  def assert_provider_failure(provider_request, status, message, api_key: "test", expected_requests: 1)
    with_serpapi_api_key(api_key) do
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

    if expected_requests.zero?
      assert_not_requested :get, SERPAPI_URL_PATTERN
    else
      assert_requested provider_request, times: expected_requests
    end
  end

  def stub_serpapi_request(body: nil, status: 200, error: nil)
    request = stub_request(:get, SERPAPI_URL_PATTERN)
    return request.to_raise(error) if error

    request.to_return(status: status, body: body)
  end

  def with_serpapi_api_key(api_key)
    original_api_key = ENV["SERPAPI_API_KEY"]
    ENV["SERPAPI_API_KEY"] = api_key
    yield
  ensure
    if original_api_key.nil?
      ENV.delete("SERPAPI_API_KEY")
    else
      ENV["SERPAPI_API_KEY"] = original_api_key
    end
  end
end
