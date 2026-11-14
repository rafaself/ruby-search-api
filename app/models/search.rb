class Search < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  validates :query, presence: true
  validates :status, inclusion: { in: STATUSES }
end
