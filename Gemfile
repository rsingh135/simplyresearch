source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
# gem "sqlite3", ">= 2.1"

# Use postgreSQL as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Handle user authentication for login/signup
gem "devise", "~> 4.9", ">= 4.9.4"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

## Additional Project Gems
gem "foreman", "~> 0.88"
gem "vite_rails", "~> 3.0"

# Supports S3 for file uploads
gem "aws-sdk-s3", require: false

# Used for user sign in with google
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

# Enables background jobs
gem "good_job"

# Used for parsing PDF files
gem "pdf-reader"

# Used for Gemini integration
gem "gemini-ai", "~> 4.3"

# Used for accessing Google Drive and presentations
gem "google-apis-slides_v1", "~> 0.31.0"
gem "google-apis-drive_v3", "~> 0.69.0"

group :development, :test do
  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  gem "capybara"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"

  gem "prettier_print", "~> 1.2"
  gem "rails-controller-testing"
  gem "rspec-rails", "~> 8.0"

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop", "~> 1.78"
  gem "rubocop-rails-omakase", require: false
  gem "selenium-webdriver", "~> 4.34"
  gem "simplecov", "~> 0.22"

  gem "syntax_tree", "~> 6.3"
  gem "syntax_tree-haml", "~> 4.0"
  gem "syntax_tree-rbs", "~> 1.0"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
