Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include(PwaDirectUploadAccess) unless ActiveStorage::DirectUploadsController < PwaDirectUploadAccess
end
