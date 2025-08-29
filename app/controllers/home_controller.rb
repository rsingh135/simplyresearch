class HomeController < ApplicationController
  def index
    @document = Document.new
  end

  def about
  end
end
