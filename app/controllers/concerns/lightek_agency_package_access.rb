module LightekAgencyPackageAccess
  extend ActiveSupport::Concern
  included do
    before_action :enforce_installed_package
    around_action :meter_installed_package
    rescue_from LightekAgency::PackagePolicy::Denied do |error|
      if request.format.html?
        render plain: error.message, status: :forbidden
      else
        render json: {error: error.message}, status: :forbidden
      end
    end
  end
  private
  def package_actor
    return current_user if respond_to?(:current_user)
    defined?(Current) && Current.respond_to?(:session) ? Current.session&.user : nil
  end
  def package_feature
    LightekAgency::PackageFeatures.for_controller(controller_path, params)
  end
  def enforce_installed_package
    return if package_actor&.role == 'super_admin'
    if package_feature == 'website' && request.get? && request.path.in?(%w[/ /site/home]) && !LightekAgency::PackagePolicy.allowed?(package_actor, 'website')
      return render(template: 'managed_packages/home', layout: 'auth')
    end
    LightekAgency::PackagePolicy.authorize!(package_actor, package_feature) if package_feature
  end
  def meter_installed_package
    ids = []
    user = package_actor
    if !request.get? && !request.head? && !request.options? && user&.role != 'super_admin' && package_feature
      ids = LightekAgency::PackagePolicy.reserve_write!(user: user, feature: package_feature)
    end
    completed = false
    yield
    completed = response.status.between?(200,399) && !(respond_to?(:flash) && flash[:alert].present?)
  ensure
    LightekAgency::PackagePolicy.release_write!(ids) unless completed
  end
end
