# app/controllers/admins/omniauth_callbacks_controller.rb
class Admins::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    admin = Admin.from_google(from_google_params)

    if admin.present?
      # Capture the access and refresh tokens from the omniauth hash
      # The auth method is a helper you've already defined, so we'll use that.
      access_token = auth.credentials.token
      refresh_token = auth.credentials.refresh_token

      # Save the tokens to the admin record
      admin.update!(
        access_token: access_token,
        # Only update the refresh token if it's present. It's often nil after the first login.
        refresh_token: refresh_token || admin.refresh_token
      )

      sign_out_all_scopes
      flash[:notice] = t "devise.omniauth_callbacks.success", kind: "Google"
      sign_in_and_redirect admin, event: :authentication
    else
      flash[:alert] = t "devise.omniauth_callbacks.failure", kind: "Google", reason: "#{auth.info.email} is not authorized."
      redirect_to new_admin_session_path
    end
  end

  def from_google_params
    @from_google_params ||= {
      uid: auth.uid,
      email: auth.info.email
    }
  end

  def auth
    @auth ||= request.env["omniauth.auth"]
  end
end
