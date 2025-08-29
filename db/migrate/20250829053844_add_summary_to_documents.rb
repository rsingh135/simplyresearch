class AddSummaryToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :summary, :text
    add_column :documents, :key_points, :jsonb
    add_column :documents, :status, :string
  end
end
