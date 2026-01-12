#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install
bundle exec vite build
bundle exec vite build --ssr # If you use SSR
bundle exec rails assets:precompile
bundle exec rails assets:clean
bundle exec rails db:migrate
