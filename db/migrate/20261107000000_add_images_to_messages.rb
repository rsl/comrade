class AddImagesToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :images, :jsonb
  end
end
