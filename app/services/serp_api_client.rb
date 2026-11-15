require "net/http"
require "json"

class SerpApiClient
  ENDPOINT = URI("https://serpapi.com/search.json").freeze
  RESULT_FIELDS = %w[position title link snippet].freeze

  class Error < StandardError
    attr_reader :http_status

    def initialize(message, http_status: 502)
      @http_status = http_status
      super(message)
    end
  end

  def initialize(api_key: ENV["SERPAPI_API_KEY"], http: Net::HTTP.new(ENDPOINT.host, ENDPOINT.port))
    @api_key = api_key
    @http = http
  end

  def search(query, location: nil, hl: nil)
    if @api_key.to_s.strip.empty?
      raise Error.new("Search provider is not configured.", http_status: 503)
    end

    uri = ENDPOINT.dup
    params = { engine: "google", q: query, api_key: @api_key, async: false }
    params[:location] = location if location.present?
    params[:hl] = hl if hl.present?
    uri.query = URI.encode_www_form(params)

    @http.use_ssl = true
    @http.open_timeout = 5
    @http.write_timeout = 5
    @http.read_timeout = 30
    @http.max_retries = 0

    response = @http.get(uri.request_uri, "Accept" => "application/json")
    raise Error, "Search provider returned an HTTP error." unless response.is_a?(Net::HTTPSuccess)

    extract_results(JSON.parse(response.body.to_s))
  rescue Timeout::Error, Errno::ETIMEDOUT
    raise Error.new("Search provider timed out.", http_status: 504), cause: nil
  rescue JSON::ParserError, EncodingError
    raise Error, "Search provider returned invalid JSON.", cause: nil
  rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
         Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise Error, "Could not connect to search provider.", cause: nil
  end

  private

  def extract_results(payload)
    invalid_response! unless payload.is_a?(Hash) && payload["search_metadata"].is_a?(Hash)

    status = payload["search_metadata"]["status"]
    raise Error, "Search provider could not complete the search." if status == "Error"
    invalid_response! unless status == "Success"

    results = payload.fetch("organic_results", [])
    invalid_response! unless results.is_a?(Array)

    error = payload["error"]
    invalid_response! unless error.nil? || error.is_a?(String)

    information = payload["search_information"]
    fully_empty = results.empty? && information.is_a?(Hash) && information["organic_results_state"] == "Fully empty"
    if error && !error.empty? && !fully_empty
      raise Error, "Search provider could not complete the search."
    end

    results.first(10).map do |result|
      invalid_response! unless result.is_a?(Hash)
      invalid_response! unless result["position"].nil? || result["position"].is_a?(Integer)
      invalid_response! unless %w[title link snippet].all? { |field| result[field].nil? || result[field].is_a?(String) }

      RESULT_FIELDS.to_h { |field| [field, result[field]] }
    end
  end

  def invalid_response!
    raise Error, "Search provider returned an invalid response."
  end
end
