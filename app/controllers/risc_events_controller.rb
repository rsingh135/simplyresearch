# frozen_string_literal: true

# Controller to receive Google Cross-Account Protection (RISC) security events
# See: https://developers.google.com/identity/protocols/risc
#
# This controller inherits from ActionController::API to avoid any authentication
# callbacks that may be defined in ApplicationController or by Devise
class RiscEventsController < ActionController::API

  # POST /risc/events
  # Receives security event tokens from Google
  def create
    token = extract_token_from_request

    if token.blank?
      Rails.logger.error "[RISC] No token found in request"
      return head :bad_request
    end

    handler = RiscEventHandler.new

    begin
      # Validate and decode the security event token
      payload = handler.validate_and_decode(token)

      Rails.logger.info "[RISC] Received valid security event"

      # Handle the security event(s)
      handler.handle_event(payload)

      # Return 202 Accepted to acknowledge receipt
      head :accepted

    rescue RiscEventHandler::InvalidTokenError => e
      Rails.logger.error "[RISC] Invalid token: #{e.message}"
      head :bad_request

    rescue StandardError => e
      Rails.logger.error "[RISC] Error processing event: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      head :internal_server_error
    end
  end

  private

  def extract_token_from_request
    # RISC events are sent as application/secevent+jwt
    # The token is in the request body
    if request.content_type&.include?("secevent+jwt") || request.content_type&.include?("jwt")
      request.body.read
    elsif request.content_type&.include?("json")
      # Some implementations send as JSON
      json = JSON.parse(request.body.read) rescue {}
      json["token"] || json["security_event_token"]
    else
      # Try reading body directly
      request.body.read
    end
  end
end

