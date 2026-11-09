# Capture chunks and destination credentials must never appear in request logs.
Rails.application.config.filter_parameters += [:live_chunk, :stream_key, :server_url, :ticket]
Rails.application.config.to_prepare do
  unless ApplicationCable::Connection.ancestors.include?(Studio::Live::LogRedaction)
    ApplicationCable::Connection.prepend(Studio::Live::LogRedaction)
  end
end

Rails.application.config.filter_parameters += [:chat_embed_url, :api_secret]
Rails.application.config.filter_parameters += [:ssn_session, :sign_api_key]
