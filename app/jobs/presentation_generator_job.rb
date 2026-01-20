# Require the necessary Google API gems
require "google/apis/slides_v1"
require "google/apis/drive_v3"
require "googleauth" # For handling Google authentication


class PresentationGeneratorJob < ApplicationJob
 queue_as :default


  def perform(document_id, admin_id = nil)
    $stdout.puts "=== PresentationGeneratorJob START: Document #{document_id}, Admin #{admin_id} ==="
    $stdout.flush
    
    # Find the document and admin records.
    document = Document.find_by(id: document_id)
    unless document
      Rails.logger.error "PresentationGeneratorJob: Document (ID: #{document_id}) not found. Aborting job."
      return
    end

    # If admin_id not provided, get it from the document
    admin = admin_id ? Admin.find_by(id: admin_id) : document.admin
    unless admin
      Rails.logger.error "PresentationGeneratorJob: Admin not found for Document (ID: #{document_id}). Aborting job."
      document.update!(status: "presentation_failed", processing_step: "Failed: Admin not found")
      return
    end


    begin
      document.update!(processing_step: "Connecting to Google Slides...")
      $stdout.puts "PresentationGeneratorJob: Retrieving credentials for Admin ID: #{admin.id}"
      $stdout.puts "Admin has access_token: #{admin.access_token.present?}, refresh_token: #{admin.refresh_token.present?}"
      $stdout.flush
      
      # Retrieve credentials from the admin record.
      credentials = admin.credentials
      unless credentials
        raise "Admin (ID: #{admin_id || document.admin_id}) does not have valid Google credentials."
      end
      $stdout.puts "PresentationGeneratorJob: Credentials retrieved successfully"
      $stdout.flush


      # Initialize Google Slides service
      Rails.logger.info "PresentationGeneratorJob: Initializing Google Slides service"
      slides_service = Google::Apis::SlidesV1::SlidesService.new
      slides_service.authorization = credentials

      # Initialize Google Drive service
      Rails.logger.info "PresentationGeneratorJob: Initializing Google Drive service"
      drive_service = Google::Apis::DriveV3::DriveService.new
      drive_service.authorization = credentials


      # 1. Create a new blank Google Slides presentation using Drive service
      document.update!(processing_step: "Creating new presentation file...")
      presentation_title = document.title.presence || "AI Generated Presentation"
      presentation = drive_service.create_file(
        Google::Apis::DriveV3::File.new(
          name: presentation_title,
          mime_type: "application/vnd.google-apps.presentation"
        )
      )
      presentation_id = presentation.id


      # 2. Get the first slide
      presentation_details = slides_service.get_presentation(presentation_id, fields: "slides")


      # Part 1: Create a new blank slide
      document.update!(processing_step: "Designing slides...")
      client_requested_slide_id = "slide_#{SecureRandom.hex(4)}"
      create_slide_requests = [ {
        create_slide: {
          object_id: client_requested_slide_id,
          insertion_index: 1,
          slide_layout_reference: { predefined_layout: "BLANK" }
        }
      } ]


      create_slide_response = slides_service.batch_update_presentation(
        presentation_id,
        Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: create_slide_requests)
      )
      actual_new_slide_id = create_slide_response.replies.first.create_slide.object_id_prop.to_s


      # Part 2: Create multiple slides
      key_points = Array(document.key_points)
      slides_to_create = 1 + ((key_points.length + 1) / 2.0).ceil
      slide_ids = [ actual_new_slide_id ]
      all_shape_requests = []


      (2..slides_to_create).each do |slide_num|
        client_slide_id = "slide_#{SecureRandom.hex(4)}"
        all_shape_requests << {
          create_slide: {
            object_id: client_slide_id,
            insertion_index: slide_num - 1,
            slide_layout_reference: { predefined_layout: "BLANK" }
          }
        }
      end


      if all_shape_requests.any?
        document.update!(processing_step: "Adding key point slides...")
        create_slides_response = slides_service.batch_update_presentation(
          presentation_id,
          Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_shape_requests)
        )


        create_slides_response.replies.each do |reply|
          if reply.respond_to?(:create_slide) && reply.create_slide.respond_to?(:object_id_prop)
            slide_ids << reply.create_slide.object_id_prop.to_s
          end
        end
        sleep 1
      end


      # Reset for shape creation
      document.update!(processing_step: "Formatting text boxes...")
      all_shape_requests = []
      original_id_order = []


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


      # Abstract content
      all_shape_requests << {
        create_shape: {
          object_id: abstract_box_id,
          shape_type: "TEXT_BOX",
          element_properties: {
            page_object_id: abstract_slide_id,
            size: { height: { magnitude: 3_500_000, unit: "EMU" }, width: { magnitude: 8_500_000, unit: "EMU" } },
            transform: { scale_x: 1, scale_y: 1, translate_x: 600_000, translate_y: 750_000, unit: "EMU" }
          }
        }
      }
      original_id_order << abstract_box_id


      # Key Points slides
      key_point_text_requests = []
      key_points.each_slice(2).with_index do |points, index|
        slide_id = slide_ids[index + 1]
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


        points.each_with_index do |point, point_index|
          y_offset = 600_000 + (point_index * 1_600_000)
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
      create_all_shapes_response = slides_service.batch_update_presentation(
        presentation_id,
        Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_shape_requests)
      )


      # Extract all shape IDs
      shape_id_map = {}
      create_all_shapes_response.replies.each_with_index do |reply, index|
        if reply.respond_to?(:create_shape) && reply.create_shape.respond_to?(:object_id_prop)
          original_id = original_id_order[index]
          shape_id_map[original_id] = reply.create_shape.object_id_prop.to_s
        end
      end


      # Insert text
      document.update!(processing_step: "Writing content to slides...")
      require "set"
      all_insert_requests = []
      all_style_requests = []


      # Slide 1: Title + Abstract
      if shape_id_map[title_box_id]
        title_text = document.title.to_s
        if title_text.present?
          insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
          insert_request.object_id_prop = shape_id_map[title_box_id]
          insert_request.insertion_index = 0
          insert_request.text = title_text
          all_insert_requests << { insert_text: insert_request }


          update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
          update_style.object_id_prop = shape_id_map[title_box_id]
          update_style.fields = "fontSize,foregroundColor,bold"
          update_style.style = Google::Apis::SlidesV1::TextStyle.new(
            font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 36, unit: "PT"),
            foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
              opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0))
            ),
            bold: true
          )
          all_style_requests << { update_text_style: update_style }
        end
      end


      if shape_id_map[abstract_title_box_id]
        insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
        insert_request.object_id_prop = shape_id_map[abstract_title_box_id]
        insert_request.insertion_index = 0
        insert_request.text = "Abstract"
        all_insert_requests << { insert_text: insert_request }


        update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
        update_style.object_id_prop = shape_id_map[abstract_title_box_id]
        update_style.fields = "fontSize,foregroundColor,bold"
        update_style.style = Google::Apis::SlidesV1::TextStyle.new(
          font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 28, unit: "PT"),
          foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
            opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 1.0, green: 0.549, blue: 0.259))
          ),
          bold: true
        )
        all_style_requests << { update_text_style: update_style }
      end


      if shape_id_map[abstract_box_id]
        summary_text = document.summary.to_s
        if summary_text.present?
          insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
          insert_request.object_id_prop = shape_id_map[abstract_box_id]
          insert_request.insertion_index = 0
          insert_request.text = summary_text
          all_insert_requests << { insert_text: insert_request }


          update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
          update_style.object_id_prop = shape_id_map[abstract_box_id]
          update_style.fields = "fontSize,foregroundColor"
          update_style.style = Google::Apis::SlidesV1::TextStyle.new(
            font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 16, unit: "PT"),
            foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
              opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0))
            )
          )
          all_style_requests << { update_text_style: update_style }
        end
      end


      key_point_text_requests.each do |box_id, text, type|
        actual_id = shape_id_map[box_id]
        next unless actual_id && text.present?


        insert_request = Google::Apis::SlidesV1::InsertTextRequest.new
        insert_request.object_id_prop = actual_id
        insert_request.insertion_index = 0
        insert_request.text = text.to_s
        all_insert_requests << { insert_text: insert_request }


        update_style = Google::Apis::SlidesV1::UpdateTextStyleRequest.new
        update_style.object_id_prop = actual_id


        if type == :heading
          update_style.fields = "fontSize,foregroundColor,bold"
          update_style.style = Google::Apis::SlidesV1::TextStyle.new(
            font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 32, unit: "PT"),
            foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
              opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 1.0, green: 0.549, blue: 0.259))
            ),
            bold: true
          )
        else
          update_style.fields = "fontSize,foregroundColor"
          update_style.style = Google::Apis::SlidesV1::TextStyle.new(
            font_size: Google::Apis::SlidesV1::Dimension.new(magnitude: 18, unit: "PT"),
            foreground_color: Google::Apis::SlidesV1::OptionalColor.new(
              opaque_color: Google::Apis::SlidesV1::OpaqueColor.new(rgb_color: Google::Apis::SlidesV1::RgbColor.new(red: 0.0, green: 0.0, blue: 0.0))
            )
          )
        end
        all_style_requests << { update_text_style: update_style }
      end


      if all_insert_requests.any?
        slides_service.batch_update_presentation(
          presentation_id,
          Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_insert_requests)
        )
      end


      document.update!(processing_step: "Applying professional styling...")
      if all_style_requests.any?
        slides_service.batch_update_presentation(
          presentation_id,
          Google::Apis::SlidesV1::BatchUpdatePresentationRequest.new(requests: all_style_requests)
        )
      end


      # 6. Save the presentation URL
      document.update!(processing_step: "Almost ready!")
      presentation_url = "https://docs.google.com/presentation/d/#{presentation_id}/edit"
      document.update!(presentation_url: presentation_url, status: "presentation_generated", processing_step: "Completed")


    rescue Google::Apis::AuthorizationError => e
      error_msg = "Google OAuth Authorization Error: #{e.class}: #{e.message}"
      $stdout.puts "=== #{error_msg} ==="
      $stdout.puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
      $stdout.flush
      Rails.logger.error error_msg
      document.update!(status: "presentation_failed", processing_step: "Failed: Authorization error - #{e.message}")
    rescue StandardError => e
      error_msg = "PresentationGeneratorJob ERROR: #{e.class}: #{e.message}"
      $stdout.puts "=== #{error_msg} ==="
      $stdout.puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
      $stdout.flush
      Rails.logger.error error_msg
      document.update!(status: "presentation_failed", processing_step: "Failed: #{e.message}")
    end
  end
end
