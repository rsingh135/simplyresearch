# frozen_string_literal: true

# Service to handle Google Cross-Account Protection (RISC) security events
# See: https://developers.google.com/identity/protocols/risc
# Dependencies are loaded lazily to avoid boot-time issues

# Service to handle Google Cross-Account Protection (RISC) security events
# See: https://developers.google.com/identity/protocols/risc
class RiscEventHandler
  RISC_CONFIG_URL = "https://accounts.google.com/.well-known/risc-configuration"
  GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"

  class InvalidTokenError < StandardError; end
  class ConfigurationError < StandardError; end

  def initialize
    @client_ids = [
      Rails.application.credentials.dig(:google, :client_id)
    ].compact
  end

  # Validate and decode a RISC security event token
  def validate_and_decode(token)
    ensure_dependencies_loaded
    raise InvalidTokenError, "Token is blank" if token.blank?

    # Decode header to get key ID
    header = JWT.decode(token, nil, false).last
    key_id = header["kid"]

    raise InvalidTokenError, "No key ID in token header" if key_id.blank?

    # Get Google's public key
    public_key = fetch_google_public_key(key_id)

    # Verify and decode the token
    decoded = JWT.decode(
      token,
      public_key,
      true, # verify signature
      {
        algorithm: "RS256",
        iss: risc_issuer,
        aud: @client_ids,
        verify_iss: true,
        verify_aud: true
      }
    )

    decoded.first
  rescue JWT::DecodeError => e
    raise InvalidTokenError, "JWT decode error: #{e.message}"
  rescue JWT::VerificationError => e
    raise InvalidTokenError, "JWT verification error: #{e.message}"
  end

  # Handle a validated security event
  def handle_event(payload)
    events = payload["events"] || {}

    events.each do |event_type, event_data|
      subject = event_data["subject"] || payload["sub_id"]
      user_identifier = extract_user_identifier(subject)

      Rails.logger.info "[RISC] Processing event: #{event_type} for user: #{user_identifier}"

      case event_type
      when "https://schemas.openid.net/secevent/risc/event-type/account-disabled"
        handle_account_disabled(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/account-enabled"
        handle_account_enabled(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/account-purged"
        handle_account_purged(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required"
        handle_credential_change_required(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/sessions-revoked"
        handle_sessions_revoked(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/tokens-revoked"
        handle_tokens_revoked(user_identifier, event_data)
      when "https://schemas.openid.net/secevent/risc/event-type/verification"
        handle_verification(event_data)
      else
        Rails.logger.warn "[RISC] Unknown event type: #{event_type}"
      end
    end
  end

  private

  def ensure_dependencies_loaded
    require "jwt"
    require "openssl"
    require "net/http"
    require "json"
    require "uri"
  end

  def risc_issuer
    ensure_dependencies_loaded
    @risc_issuer ||= fetch_risc_config["issuer"]
  end

  def fetch_risc_config
    ensure_dependencies_loaded
    @risc_config ||= begin
      uri = URI(RISC_CONFIG_URL)
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    rescue StandardError => e
      Rails.logger.error "[RISC] Failed to fetch RISC config: #{e.message}"
      # Fallback to known values
      { "issuer" => "https://accounts.google.com", "jwks_uri" => GOOGLE_CERTS_URL }
    end
  end

  def fetch_google_public_key(key_id)
    uri = URI(GOOGLE_CERTS_URL)
    response = Net::HTTP.get(uri)
    certs = JSON.parse(response)

    key_data = certs["keys"].find { |k| k["kid"] == key_id }
    raise InvalidTokenError, "Key ID #{key_id} not found in Google certs" unless key_data

    # Build RSA public key from JWK
    build_rsa_key(key_data)
  end

  def build_rsa_key(jwk)
    # Decode the modulus and exponent from base64url
    n = base64url_decode(jwk["n"])
    e = base64url_decode(jwk["e"])

    # Create RSA key
    key = OpenSSL::PKey::RSA.new
    key.set_key(
      OpenSSL::BN.new(n, 2),
      OpenSSL::BN.new(e, 2),
      nil
    )
    key
  end

  def base64url_decode(str)
    # Add padding if needed
    str += "=" * (4 - str.length % 4) if str.length % 4 != 0
    Base64.urlsafe_decode64(str)
  end

  def extract_user_identifier(subject)
    return nil unless subject

    case subject["format"]
    when "email"
      subject["email"]
    when "iss_sub"
      subject["sub"]
    else
      subject["email"] || subject["sub"] || subject.to_s
    end
  end

  # Event handlers - implement your security logic here

  def handle_account_disabled(user_identifier, event_data)
    Rails.logger.warn "[RISC] Account disabled for: #{user_identifier}, reason: #{event_data['reason']}"

    admin = find_admin_by_identifier(user_identifier)
    return unless admin

    # Disable Google sign-in for this user
    admin.update(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )

    Rails.logger.info "[RISC] Cleared OAuth tokens for disabled account: #{admin.email}"
  end

  def handle_account_enabled(user_identifier, _event_data)
    Rails.logger.info "[RISC] Account re-enabled for: #{user_identifier}"
    # User can sign in again normally
  end

  def handle_account_purged(user_identifier, _event_data)
    Rails.logger.warn "[RISC] Account purged for: #{user_identifier}"

    admin = find_admin_by_identifier(user_identifier)
    return unless admin

    # Clear OAuth tokens and potentially mark account
    admin.update(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )

    Rails.logger.info "[RISC] Cleared OAuth tokens for purged account: #{admin.email}"
  end

  def handle_credential_change_required(user_identifier, _event_data)
    Rails.logger.warn "[RISC] Credential change required for: #{user_identifier}"

    admin = find_admin_by_identifier(user_identifier)
    return unless admin

    # Force re-authentication by clearing tokens
    admin.update(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )

    Rails.logger.info "[RISC] Cleared OAuth tokens, requiring re-auth for: #{admin.email}"
  end

  def handle_sessions_revoked(user_identifier, _event_data)
    Rails.logger.warn "[RISC] Sessions revoked for: #{user_identifier}"

    admin = find_admin_by_identifier(user_identifier)
    return unless admin

    # Clear OAuth tokens to force re-authentication
    admin.update(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )

    Rails.logger.info "[RISC] Cleared OAuth tokens due to session revocation: #{admin.email}"
  end

  def handle_tokens_revoked(user_identifier, _event_data)
    Rails.logger.warn "[RISC] Tokens revoked for: #{user_identifier}"

    admin = find_admin_by_identifier(user_identifier)
    return unless admin

    # Clear stored tokens
    admin.update(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )

    Rails.logger.info "[RISC] Cleared revoked OAuth tokens for: #{admin.email}"
  end

  def handle_verification(event_data)
    Rails.logger.info "[RISC] Verification event received: #{event_data['state']}"
    # This is a test event from Google to verify your endpoint
  end

  def find_admin_by_identifier(identifier)
    return nil if identifier.blank?

    # Try to find by email first, then by UID
    Admin.find_by(email: identifier) || Admin.find_by(uid: identifier)
  end
end

