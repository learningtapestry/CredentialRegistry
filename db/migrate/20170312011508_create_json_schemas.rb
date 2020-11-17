class CreateJsonSchemas < ActiveRecord::Migration[4.2]
  def change
    create_table :json_schemas do |t|
      t.string :name, null: false, index: true
      t.jsonb  :schema, null: false, default: '{}'

      t.timestamps null: false
    end
  end
end
