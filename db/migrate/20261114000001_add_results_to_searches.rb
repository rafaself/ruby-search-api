class AddResultsToSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :searches, :results, :json, null: false, default: []
  end
end
