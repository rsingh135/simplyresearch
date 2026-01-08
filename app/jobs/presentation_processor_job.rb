require "pdf-reader"
require "open-uri"
require "json" # Required for JSON parsing/generating
require "net/http" # Required for direct HTTP requests
require "uri" # Required for URI parsing


class PresentationProcessorJob < ApplicationJob
 queue_as :default


 def perform(document_id)
   Rails.logger.info "=== PresentationProcessorJob started for Document ID: #{document_id} ==="
   document = Document.find_by(id: document_id)

   unless document
     Rails.logger.error "PresentationProcessorJob: Document with ID #{document_id} not found!"
     return
   end

   unless document.pdf.attached?
     Rails.logger.error "PresentationProcessorJob: Document #{document_id} has no PDF attached!"
     document.update!(status: "processing_failed")
     return
   end

   Rails.logger.info "PresentationProcessorJob: Setting status to 'processing' for Document #{document_id}"
   document.update!(status: "processing")


   begin
     # 1. Download PDF from S3
     pdf_data = URI.open(document.pdf.url).read


     # 2. Parse PDF content
     pdf_reader = PDF::Reader.new(StringIO.new(pdf_data))
     text_content = ""
     pdf_reader.pages.each do |page|
       text_content += page.text + "\n"
     end


     if text_content.strip.empty?
       raise "PDF contains no extractable text."
     end


     # --- Direct Gemini API Call using Net::HTTP ---
     api_key = Rails.application.credentials.dig(:google, :gemini_api_key)
     unless api_key
       raise "Gemini API key is not configured. Please set it in Rails credentials."
     end

     # Use Gemini 2.5 Flash - latest stable model as of 2025
     # Alternative models if this fails: gemini-2.0-flash, gemini-1.5-flash, gemini-pro
     model_name = "gemini-2.5-flash"
     api_version = "v1beta" # v1beta typically has access to latest models


     # Construct the full URI with the correct API version and model
     uri = URI.parse("https://generativelanguage.googleapis.com/#{api_version}/models/#{model_name}:generateContent?key=#{api_key}")
     http = Net::HTTP.new(uri.host, uri.port)
     http.use_ssl = true # Use SSL for secure connection


     prompt_text = <<-PROMPT
     You are an expert academic summarizer.
     Summarize the following research paper text into a concise abstract and extract 5-7 key bullet points.
     Format the output as:
     Abstract: [Concise abstract here]
     Key Points:
     - [Key point 1]
     - [Key point 2]
     - ...


     Research Paper Text:
     #{text_content.truncate(15000)}
     PROMPT


     # Prepare the request payload
     request_payload = {
       contents: [
         {
           role: "user",
           parts: [
             { text: prompt_text }
           ]
         }
       ]
     }.to_json


     # Create the POST request
     request = Net::HTTP::Post.new(uri.request_uri)
     request["Content-Type"] = "application/json"
     request.body = request_payload


     # Make the request and get the response
     response = http.request(request)


     # Process the response
     if response.is_a?(Net::HTTPSuccess)
       response_body = JSON.parse(response.body)
       gemini_output = response_body.dig("candidates", 0, "content", "parts", 0, "text")


       if gemini_output.nil? || gemini_output.empty?
         raise "Gemini API did not return expected text content."
       end
     else
       error_message = "Gemini API call failed with HTTP status #{response.code}. Response: #{response.body}"
       raise error_message
     end
     # --- End Direct Gemini API Call ---


     # 4. Parse the Gemini output in Ruby
     summary_lines = gemini_output.split("Key Points:")
     abstract = summary_lines[0].gsub("Abstract:", "").strip
     key_points_text = summary_lines[1]&.strip || ""
     key_points = key_points_text.split("\n").map { |kp| kp.strip.delete_prefix("- ") }.reject(&:empty?)


     # 5. Store the results in the database
     Rails.logger.info "PresentationProcessorJob: Updating Document #{document_id} with summary and key points"
     document.update!(
       summary: abstract,
       key_points: key_points,
       status: "generated"
     )

     Rails.logger.info "=== PresentationProcessorJob completed successfully for Document #{document_id} ==="
     Rails.logger.info "Document #{document.id} status: #{document.reload.status}"
     puts "Document #{document.id} processed by AI successfully!"


   rescue StandardError => e
     error_message = "#{e.class}: #{e.message}"
     Rails.logger.error "=== PresentationProcessorJob ERROR for Document #{document_id} ==="
     Rails.logger.error "Error: #{error_message}"
     Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"

     # Store error message in document summary field temporarily for debugging
     document.update!(
       status: "processing_failed",
       summary: "ERROR: #{error_message}\n\nCheck Rails logs for full details."
     )

     Rails.logger.error "=== PresentationProcessorJob failed, status set to 'processing_failed' ==="

     # Re-raise to ensure GoodJob captures the error
     raise
   end
 end
end
