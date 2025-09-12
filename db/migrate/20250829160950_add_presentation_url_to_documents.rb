class AddPresentationUrlToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :presentation_url, :string
  end
end
