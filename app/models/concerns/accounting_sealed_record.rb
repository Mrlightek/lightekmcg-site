module AccountingSealedRecord
  extend ActiveSupport::Concern
  included do
    after_initialize { self.record_key ||= SecureRandom.uuid }
    before_validation do
      if @pending_accounting_data
        self.record_key ||= SecureRandom.uuid
        self.sealed_data = LightekIdentity::Sealed.pack(@pending_accounting_data, context: "#{self.class.name}:#{book_id}:#{record_key}")
      end
    end
    after_save { @pending_accounting_data = nil }
    validates :record_key, :sealed_data, presence: true
  end
  def data
    @pending_accounting_data || LightekIdentity::Sealed.open(sealed_data, context: "#{self.class.name}:#{book_id}:#{record_key}")
  end
  def data=(value)
    raise ArgumentError, 'Financial payload must be an object' unless value.is_a?(Hash)
    @pending_accounting_data = value.deep_stringify_keys
  end
  def reload(*)
    @pending_accounting_data = nil
    super
  end
end
