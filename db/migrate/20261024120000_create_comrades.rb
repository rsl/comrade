# Identity: named comrades with an authless token — the token remembers,
# nothing verifies. conversations.comrade_id is nullable on purpose: nil
# IS the commune, the shared anon space (no owner ≠ owner unknown).
class CreateComrades < ActiveRecord::Migration[8.1]
  def change
    create_table :comrades do |t|
      t.string :token, null: false
      t.string :name, null: false
      t.jsonb :prefs
      t.jsonb :calibration

      t.timestamps
    end
    add_index :comrades, :token, unique: true
    add_index :comrades, :name, unique: true

    add_reference :conversations, :comrade, foreign_key: true
  end
end