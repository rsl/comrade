class AddStatsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :stats, :jsonb
  end
end