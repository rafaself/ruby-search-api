class Search < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  validates :query, presence: true
  validates :status, inclusion: { in: STATUSES }

  def perform!(client: SerpApiClient.new)
    update!(status: "processing")
    organic_results = client.search(query, location: location, hl: hl)
    update!(status: "completed", results: organic_results)
  rescue SerpApiClient::Error
    update!(status: "failed", results: [])
    raise
  end
end
