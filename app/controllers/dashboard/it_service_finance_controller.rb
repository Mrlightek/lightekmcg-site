class Dashboard::ItServiceFinanceController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  include LightekIdentity::SensitiveSession
  protect_from_forgery with: :exception
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_sensitive_session!
  before_action :finance_context!
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from ItServices::TechnicianPayout::Invalid, LightekPeople::Payroll::Invalid, ActiveRecord::RecordInvalid, with: :finance_error

  def index
    @access.require!(:read)
    @plans = ItServices::Plan.joins(:product).where(lightek_commerce_products: { site_id: @site.id }).includes(:product, :resource)
    @products = LightekCommerce::Product.where(site: @site, product_type: "service", billing_interval: %w[month year])
      .where.not(id: @plans.select(:product_id)).order(:name)
    @resources = LightekReservations::Resource.where(site: @site, kind: "service", product_id: nil)
      .where.not(id: @plans.select(:resource_id)).order(:name)
    @appointment_resources = LightekReservations::Resource.joins(:product).where(site: @site, kind: "service")
      .where(lightek_commerce_products: { billing_interval: "one_time" }).order(:name)
    @requests = if ItServices::Enrollment.operations_ready?
      ItServices::TechnicianPayout.requests_for(@site).includes(:technician, :reservation).order(closed_at: :desc).limit(100).to_a
    else
      []
    end
    @payouts = ItServices::Payout.where(employer: @access.employer, service_request_id: @requests.map(&:id))
      .includes(pay_statement: :pay_run).index_by(&:service_request_id)
    @runs = LightekPeople::PayRun.where(employer: @access.employer, status: "draft").order(period_end: :desc, id: :desc)
  end

  def create_plan
    @access.require!(:owner)
    product = LightekCommerce::Product.where(site: @site).find(params.require(:product_id))
    resource = LightekReservations::Resource.where(site: @site).find(params.require(:resource_id))
    product.with_lock do
      resource.with_lock do
        existing = ItServices::Plan.find_by(product: product)
        next if existing&.resource_id == resource.id
        if existing || ItServices::Plan.exists?(resource: resource)
          raise ItServices::TechnicianPayout::Invalid, "Choose a product and service that are not already linked."
        end
        if LightekCommerce::OrderItem.where(product: product).exists? || resource.reservations.exists?
          raise ItServices::TechnicianPayout::Invalid, "Link a dedicated product and appointment before accepting their first purchase or reservation."
        end

        ItServices::Plan.create!(product: product, resource: resource)
      end
    end
    redirect_to dashboard_it_service_finance_path(site_id: @site.id), notice: "Managed IT plan linked.", status: :see_other
  end

  def mark_appointment
    @access.require!(:owner)
    resource = LightekReservations::Resource.where(site: @site, kind: "service").find(params.require(:resource_id))
    resource.with_lock do
      unless resource.product&.billing_interval == "one_time" && resource.price_cents.positive?
        raise ItServices::TechnicianPayout::Invalid, "Choose an appointment with a priced one-time product."
      end

      resource.update!(it_service_appointment: true)
    end
    redirect_to dashboard_it_service_finance_path(site_id: @site.id), notice: "IT Services appointment configured.", status: :see_other
  end

  def prepare_payout
    @access.require!(:prepare)
    run = LightekPeople::PayRun.where(employer: @access.employer).find(params.require(:run_id))
    unless params[:tax_reviewed] == "1"
      raise ItServices::TechnicianPayout::Invalid, "Confirm that taxes and deductions have been reviewed."
    end

    fields = params.expect(deductions: %i[tax_cents employer_tax_cents other_deductions_cents tax_reference])
    values = fields.to_h.symbolize_keys
    %i[tax_cents employer_tax_cents other_deductions_cents].each do |field|
      values[field] = Integer(values[field].to_s, 10, exception: false)
      raise ItServices::TechnicianPayout::Invalid, "Enter each deduction in whole cents." unless values[field] && !values[field].negative?
    end
    statement = ItServices::TechnicianPayout.new(access: @access, site: @site).prepare!(run: run,
      request_ids: params.expect(request_ids: []), gross_amounts: params.expect(gross_amounts: {}), deductions: values)
    redirect_to dashboard_people_path(employer_id: @access.employer.id, tab: "payroll", run_id: statement.pay_run_id),
      notice: "Technician payout staged for payroll approval.", status: :see_other
  end

  private

  def finance_context!
    response.headers["Cache-Control"] = "no-store, private"
    return head :forbidden if Current.session&.connect_delegation.present?

    @site = DymondSite::Site.find(params.require(:site_id))
    employer = @site.tenant
    return head :forbidden unless employer.is_a?(User)

    @access = LightekPeople::Access.new(actor: current_user, employer: employer)
  end

  def finance_error(error)
    redirect_to dashboard_it_service_finance_path(site_id: @site.id), alert: error.message, status: :see_other
  end
end
