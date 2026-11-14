require "test_helper"

class SerpApiClientTest < ActiveSupport::TestCase
  test "encodes a synchronous Google request and returns only the first ten core results" do
    results = (1..12).map do |position|
      { "position" => position, "title" => "Title #{position}", "link" => "https://example.com/#{position}",
        "snippet" => "Description", "thumbnail" => "ignored", "sitelinks" => ["ignored"] }
    end
    http = FakeHttp.new(response: http_response(success_payload(results).to_json))
    client = SerpApiClient.new(api_key: "test-secret", http: http)

    extracted = client.search("ruby & rails + café?")

    assert_equal 10, extracted.length
    assert_equal results.first.slice("position", "title", "link", "snippet"), extracted.first
    assert_equal (1..10).to_a, extracted.map { |result| result["position"] }
    assert_equal 1, http.requests.length
    uri = URI(http.requests.first.fetch(:path))
    assert_equal "/search.json", uri.path
    assert_equal({ "engine" => "google", "q" => "ruby & rails + café?", "api_key" => "test-secret", "async" => "false" },
                 URI.decode_www_form(uri.query).to_h)
    assert_equal "application/json", http.requests.first.fetch(:headers)["Accept"]
    assert_equal true, http.use_ssl
    assert_equal [5, 5, 30, 0], [http.open_timeout, http.write_timeout, http.read_timeout, http.max_retries]
  end

  test "preserves fewer than ten results and makes missing fields null" do
    http = FakeHttp.new(response: http_response(success_payload([{ "title" => "Ruby" }]).to_json))

    assert_equal [{ "position" => nil, "title" => "Ruby", "link" => nil, "snippet" => nil }],
                 SerpApiClient.new(api_key: "test", http: http).search("ruby")
  end

  test "reads the API key from the environment" do
    original = ENV["SERPAPI_API_KEY"]
    ENV["SERPAPI_API_KEY"] = "environment-test-key"
    http = FakeHttp.new(response: http_response(success_payload.to_json))

    SerpApiClient.new(http: http).search("ruby")

    assert_equal "environment-test-key", URI.decode_www_form(URI(http.requests.first[:path]).query).to_h["api_key"]
  ensure
    ENV["SERPAPI_API_KEY"] = original
  end

  test "rejects missing and blank credentials without HTTP" do
    [nil, "", " \n"].each do |key|
      http = FakeHttp.new
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: key, http: http).search("ruby") }

      assert_equal 503, error.http_status
      assert_empty http.requests
    end
  end

  test "accepts empty and absent organic results on successful responses" do
    [success_payload, { "search_metadata" => { "status" => "Success" } }].each do |payload|
      http = FakeHttp.new(response: http_response(payload.to_json))

      assert_empty SerpApiClient.new(api_key: "test", http: http).search("ruby")
    end
  end

  test "accepts the documented fully empty success even with an error message" do
    payload = { "search_metadata" => { "status" => "Success" },
                "search_information" => { "organic_results_state" => "Fully empty" },
                "error" => "Google hasn't returned any results for this query." }
    http = FakeHttp.new(response: http_response(payload.to_json))

    assert_empty SerpApiClient.new(api_key: "test", http: http).search("no matches")
  end

  test "rejects HTTP errors and redirects without returning the upstream body" do
    %w[301 400 401 429 500 503].each do |code|
      http = FakeHttp.new(response: http_response("sensitive provider error", code: code))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 502, error.http_status
      assert_equal "Search provider returned an HTTP error.", error.message
      assert_equal 1, http.requests.length
    end
  end

  test "rejects provider errors including those in HTTP 200 responses" do
    [{ "search_metadata" => { "status" => "Error" }, "error" => "sensitive error" },
     success_payload.merge("error" => "sensitive error"),
     success_payload([{ "title" => "result" }]).merge("error" => "sensitive error",
       "search_information" => { "organic_results_state" => "Fully empty" })].each do |payload|
      http = FakeHttp.new(response: http_response(payload.to_json))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 502, error.http_status
      assert_equal "Search provider could not complete the search.", error.message
    end
  end

  test "rejects malformed and empty JSON without exposing its contents" do
    ["<html>sensitive data</html>", "", '{"unclosed":'].each do |body|
      http = FakeHttp.new(response: http_response(body))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 502, error.http_status
      assert_equal "Search provider returned invalid JSON.", error.message
    end
  end

  test "rejects invalid response shapes and field types" do
    payloads = [nil, [], "text", {}, { "search_metadata" => "Success" },
                { "search_metadata" => {} }, { "search_metadata" => { "status" => "Processing" } },
                success_payload(nil), success_payload({}), success_payload([nil]), success_payload(["result"]),
                success_payload([{ "position" => "1" }]), success_payload([{ "title" => [] }]),
                success_payload([{ "link" => {} }]), success_payload([{ "snippet" => 123 }]),
                success_payload.merge("error" => {})]
    payloads.each do |payload|
      http = FakeHttp.new(response: http_response(payload.to_json))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 502, error.http_status
      assert_equal "Search provider returned an invalid response.", error.message
    end
  end

  test "maps connection read and write timeouts to 504 without retrying" do
    [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ETIMEDOUT].each do |type|
      http = FakeHttp.new(error: type.new("sensitive URI"))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 504, error.http_status
      assert_equal "Search provider timed out.", error.message
      assert_nil error.cause
      assert_equal 1, http.requests.length
    end
  end

  test "maps network TLS and protocol failures to safe 502 errors" do
    [SocketError, Errno::ECONNRESET, EOFError, OpenSSL::SSL::SSLError,
     Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError].each do |type|
      http = FakeHttp.new(error: type.new("sensitive URI"))
      error = assert_raises(SerpApiClient::Error) { SerpApiClient.new(api_key: "test", http: http).search("ruby") }

      assert_equal 502, error.http_status
      assert_equal "Could not connect to search provider.", error.message
      assert_nil error.cause
    end
  end
end
