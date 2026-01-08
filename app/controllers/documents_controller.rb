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
      flash.now[:alert] = "Document upload failed. Please check your file and try again."
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @document = Document.find_by(id: params[:id])
    unless @document
      redirect_to root_path, alert: "Document not found."
      return
    end
    unless @document.admin == current_admin
      redirect_to root_path, alert: "You don't have permission to view this document."
      nil
    end
  end

  def generate_presentation
    @document = Document.find_by(id: params[:id])
    unless @document
      redirect_to root_path, alert: "Document not found."
      return
    end
    unless @document.admin == current_admin
      redirect_to root_path, alert: "You don't have permission to generate a presentation for this document."
      return
    end

    if @document && current_admin
      PresentationGeneratorJob.perform_later(@document.id, current_admin.id)
      flash[:notice] = "Presentation is being generated. This may take a moment."
      redirect_to @document
    else
      flash[:alert] = "Could not generate presentation."
      redirect_to @document
    end
  end

  private

  def document_params
    params.require(:document).permit(:title, :pdf)
  end
end
