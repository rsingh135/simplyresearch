class Admin < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]
  has_many :documents
  has_many_attached :avatars
  def self.from_google(u)
    create_with(uid: u[:uid], provider: "google",
                password: Devise.friendly_token[0, 20]).find_or_create_by!(email: u[:email])
  end
  def credentials
    unless self.access_token.present? && self.refresh_token.present?
      raise "Missing Google OAuth tokens. Please sign in with Google again."
    end

    auth = Google::Auth::UserRefreshCredentials.new(
      access_token: self.access_token,
      refresh_token: self.refresh_token,
      expires_at: self.expires_at,
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: [ "email", "profile", "https://www.googleapis.com/auth/drive.file" ]
    )

    # Try to refresh if expired
    begin
      if auth.expired? || auth.expires_at.nil?
        auth.fetch_access_token!
        self.update!(access_token: auth.access_token, expires_at: auth.expires_at)
      end
    rescue => e
      Rails.logger.error "Failed to refresh Google OAuth token: #{e.message}"
      raise "Google OAuth token refresh failed. Please sign in with Google again to re-authenticate."
    end

    auth
  end
end
