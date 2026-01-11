class AddProcessingStepToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :processing_step, :string
  end
end
