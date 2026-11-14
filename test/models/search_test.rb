require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "defaults to pending with a JSON array and validates query and status" do
    search = Search.create!(query: "ruby")

    assert_equal "pending", search.reload.status
    assert_equal [], search.results
    assert_not Search.new(query: " ").valid?
    assert_not Search.new(query: "ruby", status: "unknown").valid?
  end

  test "persists processing before calling the client and completes with JSON results" do
    search = Search.create!(query: "ruby")
    results = [{ "position" => 1, "title" => "Ruby", "link" => "https://ruby-lang.org", "snippet" => nil }]
    http = FakeHttp.new(response: http_response(success_payload(results).to_json)) do
      assert_equal "processing", Search.find(search.id).status
      assert_equal [], Search.find(search.id).results
    end

    search.perform!(client: SerpApiClient.new(api_key: "test", http: http))

    assert_equal "completed", search.reload.status
    assert_equal results, search.results
  end

  test "persists failure and propagates the client error" do
    search = Search.create!(query: "ruby")
    http = FakeHttp.new(error: Net::ReadTimeout.new)

    error = assert_raises(SerpApiClient::Error) do
      search.perform!(client: SerpApiClient.new(api_key: "test", http: http))
    end

    assert_equal 504, error.http_status
    assert_equal "failed", search.reload.status
    assert_equal [], search.results
  end

  test "does not disguise database errors as provider failures" do
    http = FakeHttp.new(error: ActiveRecord::StatementInvalid.new("database unavailable"))
    search = Search.create!(query: "ruby")

    assert_raises(ActiveRecord::StatementInvalid) do
      search.perform!(client: SerpApiClient.new(api_key: "test", http: http))
    end
  end
end
