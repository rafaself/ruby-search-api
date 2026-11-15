ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"
require "net/http"
require "webmock/minitest"

WebMock.disable_net_connect!

module SerpApiTestHelpers
  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :write_timeout, :read_timeout, :max_retries
    attr_reader :requests

    def initialize(response: nil, error: nil, &on_request)
      @response = response
      @error = error
      @on_request = on_request
      @requests = []
    end

    def get(path, headers)
      @requests << { path: path, headers: headers }
      @on_request&.call
      raise @error if @error

      @response || raise("Unexpected HTTP request")
    end
  end

  def http_response(body, code: "200")
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "test response")
    response.instance_variable_set(:@read, true)
    response.body = body
    response
  end

  def success_payload(results = [])
    { "search_metadata" => { "status" => "Success" }, "organic_results" => results }
  end
end

class ActiveSupport::TestCase
  include SerpApiTestHelpers
end
