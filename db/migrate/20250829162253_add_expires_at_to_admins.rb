class AddExpiresAtToAdmins < ActiveRecord::Migration[8.0]
  def change
    add_column :admins, :expires_at, :datetime
  end
end
