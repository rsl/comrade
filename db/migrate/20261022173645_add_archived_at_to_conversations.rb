class AddArchivedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :archived_at, :datetime
  end
end
