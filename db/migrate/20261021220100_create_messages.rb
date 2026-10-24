class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.belongs_to :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.jsonb :citations
      t.string :tool_name
      t.jsonb :tool_payload

      t.timestamps
    end
  end
end