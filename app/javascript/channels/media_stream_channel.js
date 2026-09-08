// app/javascript/channels/media_stream_channel.js
import consumer from "./consumer"

const callId = "call-12345";

const mediaStreamChannel = consumer.subscriptions.create(
  { channel: "MediaStreamChannel", call_id: callId },
  {
    received(data) {
      // Play incoming audio chunk on the receiver's end
      playAudioChunk(data.audio_chunk);
    },

    sendAudioChunk(base64Chunk) {
      this.perform("receive", { audio_chunk: base64Chunk });
    }
  }
);