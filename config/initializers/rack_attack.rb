class Rack::Attack
  ### Configure Cache ###
  # Note: Rack::Attack needs a cache store. 
  # Rails.cache is usually ActiveSupport::Cache::MemoryStore in dev
  # and SolidCache or Redis in production.
  Rack::Attack.cache.store = Rails.cache

  ### Throttle Spammy Clients ###
  # Throttle all requests by IP (60 requests/minute)
  # This is a general safety net.
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  ### Throttle Expensive AI/API Actions ###
  # Limit PDF uploads to 5 per hour per user to control Gemini costs
  throttle('uploads/ip', limit: 5, period: 1.hour) do |req|
    if req.path == '/documents' && req.post?
      req.ip
    end
  end

  # Limit Slide Generation to 3 per hour per user to control Google API costs
  throttle('slides/ip', limit: 3, period: 1.hour) do |req|
    if req.path.include?('/generate_presentation') && req.post?
      req.ip
    end
  end

  ### Custom Response ###
  self.throttled_responder = lambda do |env|
    [ 429,  # status
      { 'Content-Type' => 'text/html' },   # headers
      ['<div style="font-family:sans-serif; text-align:center; padding-top:100px;">
          <h1>Too Many Requests</h1>
          <p>Please wait a while before uploading more documents. We do this to keep our AI costs sustainable!</p>
        </div>'] # body
    ]
  end
end
