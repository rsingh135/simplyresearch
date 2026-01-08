# Require the necessary Google API gems
require "google/apis/slides_v1"
require "google/apis/drive_v3"
require "googleauth" # For handling Google authentication


class PresentationGeneratorJob < ApplicationJob
 queue_as :default


 def perform(document_id, admin_id = nil)
   # Find the document and admin records.
   # If admin_id is not provided, get it from the document's admin relationship
   document = Document.find_by(id: document_id)
   unless document
     Rails.logger.error "PresentationGeneratorJob: Document (ID: #{document_id}) not found. Aborting job."
     return
   end

   # If admin_id not provided, get it from the document
   admin = admin_id ? Admin.find_by(id: admin_id) : document.admin
   unless admin
     Rails.logger.error "PresentationGeneratorJob: Admin not found for Document (ID: #{document_id}). Aborting job."
     return
   end


   begin
     # Retrieve credentials from the admin record.
     # The credentials method should automatically refresh the token if expired.
     credentials = admin.credentials
     unless credentials
       raise "Admin (ID: #{admin_id || document.admin_id}) does not have valid Google credentials."
     end

     # Verify credentials are valid before proceeding
     if credentials.expired? && credentials.refresh_token.nil?
       raise "Google OAuth refresh token is missing. Please sign in with Google again to re-authenticate."
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

    # Part 2: Create multiple slides with better styling
    # Slide 1: Title + Abstract
    # Slides 2+: Key Points (2 per slide)

    key_points = Array(document.key_points)
    slides_to_create = 1 + ((key_points.length + 1) / 2.0).ceil # 1 for abstract + 1 per 2 key points

    Rails.logger.info "Creating #{slides_to_create} slides: 1 for abstract, #{(slides_to_create - 1)} for key points"

    all_shape_requests = []
    slide_ids = [ actual_new_slide_id ] # First slide already created

    # Create additional slides for key points if needed
    (2..slides_to_create).each do |slide_num|
      client_slide_id = "slide_#{SecureRandom.hex(4)}"
      all_shape_requests << {
        create_slide: {
          object_id: client_slide_id,
          insertion_index: slide_num - 1,
          slide_layout_reference: {
            predefined_layout: "BLANK"
          }
        }
      }
    end

    # Send request to create all additional slides
    if all_shape_requests.any?
      Rails.logger.info "Creating #{slides_to_create - 1} additional slides for key points..."
      create_slides_response = slides_service.batch_update_presentation(
        presentation_id,
        Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_shape_requests)
      )

      # Extract slide IDs from response
      create_slides_response.replies.each do |reply|
        if reply.respond_to?(:create_slide) && reply.create_slide.respond_to?(:object_id_prop)
          slide_ids << reply.create_slide.object_id_prop.to_s
        end
      end

      Rails.logger.info "Created #{slide_ids.length - 1} additional slides. Total slides: #{slide_ids.length}"
      sleep 2 # Wait for slides to materialize
    end

    # Reset for shape creation
    all_shape_requests = []
    original_id_order = [] # Track original IDs in the order they're created

    # Slide 1: Title + Abstract
    abstract_slide_id = slide_ids[0]
    title_box_id = "title_box_#{SecureRandom.hex(4)}"
    abstract_title_box_id = "abstract_title_#{SecureRandom.hex(4)}"
    abstract_box_id = "abstract_box_#{SecureRandom.hex(4)}"

    # Title on slide 1
    all_shape_requests << {
      create_shape: {
        object_id: title_box_id,
        shape_type: "TEXT_BOX",
        element_properties: {
          page_object_id: abstract_slide_id,
          size: { height: { magnitude: 120_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
          transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: 50_000, unit: "EMU" }
        }
      }
    }
    original_id_order << title_box_id

    # "Abstract" heading
    all_shape_requests << {
      create_shape: {
        object_id: abstract_title_box_id,
        shape_type: "TEXT_BOX",
        element_properties: {
          page_object_id: abstract_slide_id,
          size: { height: { magnitude: 100_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
          transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: 220_000, unit: "EMU" }
        }
      }
    }
    original_id_order << abstract_title_box_id

    # Abstract content - significantly increased spacing from heading
    all_shape_requests << {
      create_shape: {
        object_id: abstract_box_id,
        shape_type: "TEXT_BOX",
        element_properties: {
          page_object_id: abstract_slide_id,
          size: { height: { magnitude: 3_500_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
          transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: 750_000, unit: "EMU" } # Much more spacing - increased from 600_000 to 750_000
        }
      }
    }
    original_id_order << abstract_box_id

    # Key Points slides (2 points per slide)
    key_point_text_requests = []

    key_points.each_slice(2).with_index do |points, index|
      slide_id = slide_ids[index + 1]
      slide_num = index + 2

      Rails.logger.info "Creating shapes for key points slide #{slide_num} with #{points.length} points"

      # "Key Points" heading - increased spacing
      heading_box_id = "kp_heading_#{SecureRandom.hex(4)}"
      all_shape_requests << {
        create_shape: {
          object_id: heading_box_id,
          shape_type: "TEXT_BOX",
          element_properties: {
            page_object_id: slide_id,
            size: { height: { magnitude: 120_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
            transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: 80_000, unit: "EMU" }
          }
        }
      }
      original_id_order << heading_box_id
      key_point_text_requests << [ heading_box_id, "Key Points", :heading ]

      # Create a text box for each key point - significantly increased spacing from heading
      points.each_with_index do |point, point_index|
        y_offset = 600_000 + (point_index * 1_600_000) # Much more space from heading (increased to 600_000) and between points (increased to 1.6M)
        point_box_id = "kp_box_#{SecureRandom.hex(4)}"

        all_shape_requests << {
          create_shape: {
            object_id: point_box_id,
            shape_type: "TEXT_BOX",
            element_properties: {
              page_object_id: slide_id,
              size: { height: { magnitude: 1_000_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
              transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: y_offset, unit: "EMU" }
            }
          }
        }
        original_id_order << point_box_id
        key_point_text_requests << [ point_box_id, "• #{point}", :point ]
      end
    end

    # Send batch to create all shapes
    Rails.logger.info "Creating all shapes (#{all_shape_requests.length} shapes across #{slide_ids.length} slides)..."
    create_all_shapes_response = slides_service.batch_update_presentation(
      presentation_id,
      Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_shape_requests)
    )

    # Extract all shape IDs - map in the same order as requests
    shape_id_map = {}
    create_all_shapes_response.replies.each_with_index do |reply, index|
      if reply.respond_to?(:create_shape) && reply.create_shape.respond_to?(:object_id_prop)
        original_id = original_id_order[index]
        actual_id = reply.create_shape.object_id_prop.to_s
        shape_id_map[original_id] = actual_id
        Rails.logger.info "Mapped #{original_id} -> #{actual_id}"
      else
        Rails.logger.warn "Unexpected reply structure at index #{index}: #{reply.inspect}"
      end
    end

    Rails.logger.info "Successfully mapped #{shape_id_map.length} shapes out of #{original_id_order.length} requested"

    if shape_id_map.length != original_id_order.length
      Rails.logger.error "Shape ID mapping mismatch! Expected #{original_id_order.length} shapes but only got #{shape_id_map.length}"
      raise "Failed to map all shape IDs correctly"
    end

    sleep 2 # Wait for shapes to materialize

    # Now insert text first, then apply styling in separate batches
    # We need to insert all text first, then style it

    require "set"
    all_insert_requests = []
    all_style_requests = []
    shapes_with_text = Set.new # Track which shapes will have text inserted (only style these)

    # Slide 1: Title + Abstract
    if shape_id_map[title_box_id]
      # Title text
      title_text = document.title.to_s
      if title_text.present?
        insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
        insert_request.object_id_prop = shape_id_map[title_box_id]
        insert_request.insertion_index = 0
        insert_request.text = title_text
        all_insert_requests << { insert_text: insert_request }
        shapes_with_text.add(shape_id_map[title_box_id])

        # Style title (will apply after text is inserted)
        update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
        update_style.object_id_prop = shape_id_map[title_box_id]
        update_style.fields = "fontSize,foregroundColor,bold"
        update_style.style = Google::Apis::SlidesV1::TextStyle.new(
        font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 36, unit: "PT"),
        foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
          opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(
            rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0) # Pure black
          )
        ),
        bold: true
        )
        all_style_requests << { update_text_style: update_style }
      else
        Rails.logger.warn "Document title is empty, skipping title text insertion"
      end
    end

    # Abstract heading
    if shape_id_map[abstract_title_box_id]
      insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
      insert_request.object_id_prop = shape_id_map[abstract_title_box_id]
      insert_request.insertion_index = 0
      insert_request.text = "Abstract"
      all_insert_requests << { insert_text: insert_request }
      shapes_with_text.add(shape_id_map[abstract_title_box_id])

      # Style abstract heading
      update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
      update_style.object_id_prop = shape_id_map[abstract_title_box_id]
      update_style.fields = "fontSize,foregroundColor,bold"
      update_style.style = Google::Apis::SlidesV1::TextStyle.new(
        font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 28, unit: "PT"),
        foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
          opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(
            rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 1.0, green: 0.549, blue: 0.259) # Orange #FF8C42
          )
        ),
        bold: true
      )
      all_style_requests << { update_text_style: update_style }
    end

    # Abstract content
    if shape_id_map[abstract_box_id]
      summary_text = document.summary.to_s
      if summary_text.present?
        insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
        insert_request.object_id_prop = shape_id_map[abstract_box_id]
        insert_request.insertion_index = 0
        insert_request.text = summary_text
        all_insert_requests << { insert_text: insert_request }
        shapes_with_text.add(shape_id_map[abstract_box_id])

        # Style abstract text - changed to black
        update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
        update_style.object_id_prop = shape_id_map[abstract_box_id]
        update_style.fields = "fontSize,foregroundColor"
        update_style.style = Google::Apis::SlidesV1::TextStyle.new(
          font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 16, unit: "PT"),
          foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
            opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(
              rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0) # Pure black
            )
          )
        )
        all_style_requests << { update_text_style: update_style }
      else
        Rails.logger.warn "Document summary is empty, skipping abstract text insertion"
      end
    end

    # Key points text and styling
    key_point_text_requests.each do |box_id, text, type|
      actual_id = shape_id_map[box_id]
      unless actual_id
        Rails.logger.warn "Shape ID not found in map for #{box_id}, skipping"
        next
      end

      unless text.present?
        Rails.logger.warn "Text is empty for #{box_id}, skipping"
        next
      end

      insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
      insert_request.object_id_prop = actual_id
      insert_request.insertion_index = 0
      insert_request.text = text.to_s
      all_insert_requests << { insert_text: insert_request }
      shapes_with_text.add(actual_id)

      # Style based on type (only if we're inserting text)
      update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
      update_style.object_id_prop = actual_id

      if type == :heading
        update_style.fields = "fontSize,foregroundColor,bold"
        update_style.style = Google::Apis::SlidesV1::TextStyle.new(
          font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 32, unit: "PT"),
          foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
            opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(
              rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 1.0, green: 0.549, blue: 0.259) # Orange
            )
          ),
          bold: true
        )
      else # :point
        update_style.fields = "fontSize,foregroundColor"
        update_style.style = Google::Apis::SlidesV1::TextStyle.new(
          font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 18, unit: "PT"),
          foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
            opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(
              rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0) # Pure black
            )
          )
        )
      end
      all_style_requests << { update_text_style: update_style }
    end

    # First batch: Insert all text
    Rails.logger.info "Inserting text (#{all_insert_requests.length} requests)..."
    if all_insert_requests.empty?
      Rails.logger.warn "No text insert requests to send!"
    else
      begin
        insert_response = slides_service.batch_update_presentation(
          presentation_id,
          Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_insert_requests)
        )
        Rails.logger.info "Successfully inserted text into #{insert_response.replies.length} shapes"
      rescue => e
        Rails.logger.error "Error inserting text: #{e.class}: #{e.message}"
        raise e
      end
    end

    sleep 2 # Delay to ensure text is fully inserted before styling

    # Second batch: Apply all styling
    Rails.logger.info "Applying styles (#{all_style_requests.length} requests)..."
    if all_style_requests.empty?
      Rails.logger.warn "No style requests to send!"
    else
      begin
        style_response = slides_service.batch_update_presentation(
          presentation_id,
          Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_style_requests)
        )
        Rails.logger.info "Successfully styled #{style_response.replies.length} shapes"
      rescue => e
        Rails.logger.error "Error applying styles: #{e.class}: #{e.message}"
        Rails.logger.error "This might mean some shapes don't have text yet. Check that all text was inserted."
        raise e
      end
    end

    Rails.logger.info "Presentation created successfully with #{slide_ids.length} slides!"


     # 6. Save the presentation URL and update document status
     presentation_url = "https://docs.google.com/presentation/d/#{presentation_id}/edit"
     document.update!(presentation_url: presentation_url, status: "presentation_generated")
     Rails.logger.info "Document (ID: #{document_id}) updated with presentation URL: #{presentation_url} and status: 'presentation_generated'."


   rescue Google::Apis::AuthorizationError => e
     # Catch Google OAuth authorization errors (401 Unauthorized)
     Rails.logger.error "=== Google OAuth Authorization Error for Document #{document_id} ==="
     Rails.logger.error "Error: #{e.message}"
     Rails.logger.error "This usually means the OAuth token has expired or is invalid."
     Rails.logger.error "User needs to sign in with Google again to refresh their credentials."
     document.update!(status: "presentation_failed")
   rescue Google::Apis::ClientError => e
     # Catch other Google API client errors
     Rails.logger.error "=== Google API Client Error generating presentation for Document #{document_id} ==="
     Rails.logger.error "Error class: #{e.class}"
     Rails.logger.error "Error message: #{e.message}"
     Rails.logger.error "Error body: #{e.body}" if e.respond_to?(:body)
     Rails.logger.error "Full error: #{e.inspect}"
     Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
     document.update!(status: "presentation_failed")
   rescue StandardError => e
     # Catch any other unexpected errors
     Rails.logger.error "=== Unexpected error generating presentation for Document #{document_id} ==="
     Rails.logger.error "Error class: #{e.class}"
     Rails.logger.error "Error message: #{e.message}"
     Rails.logger.error "Full error: #{e.inspect}"
     Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
     document.update!(status: "presentation_failed")
   end
 end
end
