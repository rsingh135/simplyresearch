# Require the necessary Google API gems
require "google/apis/slides_v1"
require "google/apis/drive_v3"
require "googleauth" # For handling Google authentication


class PresentationGeneratorJob < ApplicationJob
 queue_as :default


 def perform(document_id, admin_id)
   # Find the document and admin records.
   # If either is not found, log a warning and return.
   document = Document.find_by(id: document_id)
   admin = Admin.find_by(id: admin_id)
   unless document && admin
     Rails.logger.warn "PresentationGeneratorJob: Document (ID: #{document_id}) or Admin (ID: #{admin_id}) not found. Aborting job."
     return # Exit early if essential records are missing
   end


   begin
     # Retrieve credentials from the admin record.
     # It's assumed that admin.credentials holds an authorized object
     # (e.g., a Google::Auth::UserRefreshCredentials instance).
     credentials = admin.credentials
     unless credentials
       raise "Admin (ID: #{admin_id}) does not have valid Google credentials."
     end


     # Initialize Google Slides service
     slides_service = Google::Apis::SlidesV1::SlidesService.new
     slides_service.authorization = credentials


     # Initialize Google Drive service (for creating the presentation file)
     drive_service = Google::Apis::DriveV3::DriveService.new
     drive_service.authorization = credentials


     # 1. Create a new blank Google Slides presentation using Drive service
     presentation_title = document.title.presence || "AI Generated Presentation" # Use presence to handle nil/empty title
     presentation = drive_service.create_file(
       Google::Apis::DriveV3::File.new(
         name: presentation_title,
         mime_type: "application/vnd.google-apps.presentation" # Correct MIME type for Google Slides
       )
     )
     presentation_id = presentation.id
     Rails.logger.info "Created new presentation with ID: #{presentation_id}, Title: '#{presentation_title}'"


     # 2. Get the first slide of the newly created presentation (to get its ID if needed for later reference)
     # We still need this to know what index to insert the new slide at.
     presentation_details = slides_service.get_presentation(presentation_id, fields: "slides")
     first_slide = presentation_details.slides.first
     unless first_slide
       raise "No slides found in the newly created presentation (ID: #{presentation_id})."
     end
     Rails.logger.info "Retrieved first slide with ID: #{first_slide.object_id}"


     Rails.logger.info "Bypassing dynamic 'Blank' layout search. Will use 'BLANK' predefined layout directly."




     # --- Strategy: Split batch updates for slide creation and combined shape/content creation ---


     # Part 1: Create a new blank slide in the presentation
     client_requested_slide_id = "slide_#{SecureRandom.hex(4)}"
     Rails.logger.info "Preparing to create a new slide with client-requested ID: #{client_requested_slide_id} using 'BLANK' predefined layout."


     create_slide_requests = [ {
       create_slide: {
         object_id: client_requested_slide_id,
         insertion_index: 1, # Insert after the first default slide (which is at index 0)
         # Use slide_layout_reference with predefined_layout directly
         slide_layout_reference: {
           predefined_layout: "BLANK"
         }
       }
     } ]


     # Send the first batch update to only create the slide
     Rails.logger.info "Sending first batch update to create the new slide."
     create_slide_response = slides_service.batch_update_presentation(
       presentation_id,
       Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: create_slide_requests)
     )
     Rails.logger.info "New slide (client-requested ID: #{client_requested_slide_id}) successfully requested with 'BLANK' layout."


     # --- Extract the actual Google-assigned object_id directly from the createSlide response ---
     actual_new_slide_id = create_slide_response.replies.first.create_slide.object_id_prop.to_s
     Rails.logger.info "Actual Google-assigned ID for the new slide obtained directly from response: #{actual_new_slide_id}."


     # --- Introduce a short delay to allow the API to fully materialize the slide ---
     # This delay is still beneficial to ensure the slide itself is fully ready before adding shapes.
     Rails.logger.info "Pausing for 3 seconds to allow the new slide to fully materialize in the API backend."
     sleep 3
     Rails.logger.info "Resuming operations after pause."

     # Part 2: Create text boxes AND insert content into them in a single request
     shape_and_content_requests = []


     # Generate unique IDs for the new text boxes (these are client-side for the request)
     new_title_box_id = "title_box_#{SecureRandom.hex(4)}"
     new_content_box_id = "content_box_#{SecureRandom.hex(4)}"


     # Request to create a text box for the title AND insert text into it
     Rails.logger.info "Creating title text box with ID: #{new_title_box_id} and inserting title text."
     shape_and_content_requests << {
       create_shape: {
         object_id: new_title_box_id,
         shape_type: "TEXT_BOX",
         element_properties: {
           page_object_id: actual_new_slide_id, # Use the actual Google-assigned slide ID here
           size: {
             height: { magnitude: 150_000, unit: "EMU" }, # Adjusted size for a title
             width: { magnitude: 8_000_000, unit: "EMU" }
           },
           transform: {
             scale_x: 1,
             scale_y: 1,
             translate_x: 700_000, # Center the title horizontally
             translate_y: 100_000,
             unit: "EMU"
           }
         },
         # Add shape_properties to set background fill
         shape_properties: {
           shape_background_fill: {
             solid_fill: {
               color: {
                 rgb_color: { red: 0.98, green: 0.98, blue: 0.98 } # Very light gray background for better contrast
               }
             }
           }
         },
         # --- CRUCIAL FIX: Add text_content directly to create_shape request ---
         text_content: {
           text_elements: [
             {
               text_run: {
                 content: document.title.to_s,
                 text_style: {
                   font_family: "Arial",
                   font_size: { magnitude: 28, unit: "PT" },
                   bold: true,
                   # Enhanced: Dark text with better contrast
                   foreground_color: {
                     rgb_color: { red: 0.1, green: 0.1, blue: 0.1 } # Dark gray for better visibility
                   }
                 }
               }
             }
           ]
         }
       }
     }


     # Construct the full text for the content, including summary and key points
     full_content_text = "Abstract:\n#{document.summary}\n\nKey Points:\n" +
                         Array(document.key_points).map { |kp| "- #{kp}" }.join("\n")


     # Request to create a text box for the main content AND insert text into it
     Rails.logger.info "Creating content text box with ID: #{new_content_box_id} and inserting content text."
     shape_and_content_requests << {
       create_shape: {
         object_id: new_content_box_id,
         shape_type: "TEXT_BOX",
         element_properties: {
           page_object_id: actual_new_slide_id, # Use the actual Google-assigned slide ID here
           size: {
             height: { magnitude: 2_000_000, unit: "EMU" }, # Larger size for content
             width: { magnitude: 8_000_000, unit: "EMU" }
           },
           transform: {
             scale_x: 1,
             scale_y: 1,
             translate_x: 700_000, # Align with title
             translate_y: 300_000, # Position below the title
             unit: "EMU"
           }
         },
         # Add shape_properties to set background fill
         shape_properties: {
           shape_background_fill: {
             solid_fill: {
               color: {
                 rgb_color: { red: 0.98, green: 0.98, blue: 0.98 } # Very light gray background for better contrast
               }
             }
           }
         },
         # --- CRUCIAL FIX: Add text_content directly to create_shape request ---
         text_content: {
           text_elements: [
             {
               text_run: {
                 content: full_content_text,
                 text_style: {
                   font_family: "Arial",
                   font_size: { magnitude: 14, unit: "PT" },
                   # Enhanced: Dark text with better contrast
                   foreground_color: {
                     rgb_color: { red: 0.1, green: 0.1, blue: 0.1 } # Dark gray for better visibility
                   }
                 }
               }
             }
           ]
         }
       }
     }


     # Send the second batch update to create shapes with their content
     if shape_and_content_requests.any?
       Rails.logger.info "Sending second batch update to create shapes with embedded content."
       # --- DEBUG LOGGING ADDITION ---
       Rails.logger.debug "Shape and content creation requests payload: #{shape_and_content_requests.inspect}"
       slides_service.batch_update_presentation(
         presentation_id,
         Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: shape_and_content_requests)
       )
       Rails.logger.info "Presentation updated successfully with new slide containing title, summary, and key points!"
     else
       Rails.logger.info "No shape and content creation requests were generated for the new slide."
     end


     # 6. Save the presentation URL and update document status
     presentation_url = "https://docs.google.com/presentation/d/#{presentation_id}/edit"
     document.update!(presentation_url: presentation_url, status: "presentation_generated")
     Rails.logger.info "Document (ID: #{document_id}) updated with presentation URL: #{presentation_url} and status: 'presentation_generated'."


   rescue Google::Apis::ClientError => e
     # Catch Google API specific errors
     Rails.logger.error "Google API Client Error generating presentation for Document #{document_id}: #{e.message}"
     Rails.logger.error "Details: #{e.body}" # Log the full error body for more context
     document.update!(status: "presentation_failed")
   rescue StandardError => e
     # Catch any other unexpected errors
     Rails.logger.error "An unexpected error occurred while generating presentation for Document #{document_id}: #{e.full_message}"
     document.update!(status: "presentation_failed")
   end
 end
end
