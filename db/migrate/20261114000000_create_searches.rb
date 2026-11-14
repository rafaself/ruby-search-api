class CreateSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :searches do |t|
      t.string :query, null: false
      t.string :status, null: false, default: "pending"

      t.timestamps null: false
    end

    add_check_constraint :searches,
                         "status IN ('pending', 'processing', 'completed', 'failed')",
                         name: "searches_status_valid"
  end
end
