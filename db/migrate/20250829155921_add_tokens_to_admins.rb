class AddTokensToAdmins < ActiveRecord::Migration[8.0]
  def change
    add_column :admins, :access_token, :string
    add_column :admins, :refresh_token, :string
  end
end
