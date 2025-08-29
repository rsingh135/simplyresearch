class DocumentsController < ApplicationController
  before_action :authenticate_admin!

  def new
    @document = current_admin.documents.new
  end

  def create
    @document = current_admin.documents.new(document_params)
    if @document.save
      PresentationProcessorJob.perform_later(@document.id)
      redirect_to @document, notice: "Document was successfully uploaded."
    else
      render :new, notice: "Document upload failed."
    end
  end

  def show
    @document = Document.find(params[:id])
  end

  private

  def document_params
    params.require(:document).permit(:title, :pdf)
  end
end
