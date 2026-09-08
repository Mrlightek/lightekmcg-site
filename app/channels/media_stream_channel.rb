class MediaStreamChannel < ApplicationCable::Channel
  def subscribed
    # Stream for a specific session/call ID
    stream_from "media_stream_#{params[:call_id]}"
  end

  def receive(data)
    # Receive binary base64 audio chunks from clients
    payload_chunk = data["audio_chunk"]

    # Save to DB / track request
    db_request = DatabaseRequest.create!(
      requestable_type: "VoipChunk",
      payload: { call_id: params[:call_id], chunk: payload_chunk }.to_json,
      occurred_at: Time.current
    )

    # Re-broadcast chunk to recipient in real-time
    ActionCable.server.broadcast("media_stream_#{params[:call_id]}", {
      sender_id: current_user&.id,
      audio_chunk: payload_chunk
    })
  end
end