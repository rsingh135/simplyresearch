class DocumentsController < ApplicationController
  before_action :authenticate_admin!

  def new
    @document = current_admin.documents.new
  end

  def create
    @document = current_admin.documents.new(document_params)
    if @document.save
      # Set initial status to 'pending' so we know the job hasn't started yet
      @document.update(status: "pending")
      Rails.logger.info "=== Enqueuing PresentationProcessorJob for Document ID: #{@document.id} ==="
      job = PresentationProcessorJob.perform_later(@document.id)
      Rails.logger.info "Job enqueued with ActiveJob ID: #{job.job_id}"
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
      @document.update(status: "generating_presentation")
      PresentationGeneratorJob.perform_later(@document.id, current_admin.id)
      flash[:notice] = "Presentation is being generated. This may take a moment."
      redirect_to @document
    else
      flash[:alert] = "Could not generate presentation."
      redirect_to @document
    end
  end

  def status
    @document = Document.find_by(id: params[:id])
    unless @document
      render json: { error: "Document not found." }, status: :not_found
      return
    end
    unless @document.admin == current_admin
      render json: { error: "Unauthorized." }, status: :unauthorized
      return
    end

    render json: {
      status: @document.status || "pending",
      summary: @document.summary,
      key_points: @document.key_points,
      presentation_url: @document.presentation_url
    }
  end

  private

  def document_params
    params.require(:document).permit(:title, :pdf)
  end
end
