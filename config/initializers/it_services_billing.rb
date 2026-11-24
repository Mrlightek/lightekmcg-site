Rails.application.config.to_prepare do
  clearance = "ItServices::PaymentClearance".safe_constantize
  if clearance
    extension = ItServices::CoveredPaymentClearance
    clearance.singleton_class.prepend(extension) unless clearance.singleton_class.ancestors.include?(extension)
  end

  request = "ItServiceRequest".safe_constantize
  extension = ItServices::SettlesCompletedAppointments
  request.include(extension) if request && !request.ancestors.include?(extension)
end
