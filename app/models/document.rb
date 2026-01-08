class Document < ApplicationRecord
  belongs_to :admin
  # more explicit naming to indicate file type is pdf, can change later if necessary
  has_one_attached :pdf, service: :amazon

  # validates :title, presence: true
  # validates :pdf_attached
  # validate :pdf_content_type
end
