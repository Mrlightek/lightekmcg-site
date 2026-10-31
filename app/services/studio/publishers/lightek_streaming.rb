module Studio
  module Publishers
    # The native streaming and OTT clients consume the same authorized media
    # catalog as the PWA. Publishing does not create a second content store.
    class LightekStreaming < LightekSocial
      def call
        raise ArgumentError,"OTT publishing requires a video master" unless publication.artifact.file.blob.content_type.start_with?("video/")
        super
      end
    end
  end
end
