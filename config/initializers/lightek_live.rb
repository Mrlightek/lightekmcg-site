# Capture chunks and destination credentials must never appear in request logs.
Rails.application.config.filter_parameters += [:live_chunk, :stream_key, :server_url, :ticket]
Rails.application.config.to_prepare do
  unless ApplicationCable::Connection.ancestors.include?(Studio::Live::LogRedaction)
    ApplicationCable::Connection.prepend(Studio::Live::LogRedaction)
  end
end
