class AddLocationAndHlToSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :searches, :location, :string
    add_column :searches, :hl, :string
  end
end
