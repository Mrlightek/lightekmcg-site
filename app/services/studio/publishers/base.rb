module Studio
  module Publishers
    class NotConfigured < StandardError; end

    class Base
      def initialize(publication)
        @publication = publication
      end

      def call
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      protected

      attr_reader :publication

      def credentials!(slug:, purpose: "media_publishing")
        Studio::Credentials.checkout!(
          slug: slug,
          consumer: self.class.name,
          purpose: purpose
        )
      end
    end
  end
end
