class Dashboard::ExecutiveTravelController < DymondDash::ApplicationController
  protect_from_forgery with: :exception
  include LightekIdentity::SensitiveSession
  before_action :authorize_travel
  before_action :require_sensitive_session!
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, NevaehOs::TravelSupplier::Unavailable do |error|
    redirect_to dashboard_executive_travel_path(@case), alert: error.message, status: :see_other
  end

  def index
    @bookings = bookings.order(id: :desc).limit(30)
  end

  def configure
    NevaehOs::TravelSupplier.configure!(current_user, params.require(:access_token))
    back('Travel supplier connected.')
  end

  def search
    require_open!
    @search_kind = params.require(:kind)
    case @search_kind
    when 'flight'
      origin, destination, departure, returning = params.require(:travel_search).values_at(:origin, :destination, :departure, :returning)
      @results = supplier.search_flights(origin: origin, destination: destination, departure: departure, returning: returning)
    when 'hotel'
      latitude, longitude, check_in, check_out = params.require(:travel_search).values_at(:latitude, :longitude, :check_in, :check_out)
      @results = supplier.search_hotels(latitude: latitude, longitude: longitude, check_in: check_in, check_out: check_out)
    else
      raise ArgumentError, 'Choose a search type.'
    end
    index
    render :index
  end

  def rates
    require_open!
    @search_kind = 'rate'
    @results = supplier.hotel_rates(params.require(:search_result_id))
    index
    render :index
  end

  def quote
    fields = params.require(:travel_quote).permit(:kind, :source_id)
    kind, source = fields.values_at(:kind, :source_id)
    values = supplier.quote(kind, source).stringify_keys
    if kind == 'flight'
      raise ArgumentError, 'Choose an offer for one passenger.' unless values.fetch('passenger_ids').one?
    elsif values.fetch('guest_count') > 1
      raise ArgumentError, 'Choose a rate for one guest.'
    end
    amount, currency = values.values_at('amount', 'currency')
    unless amount.to_s.match?(/\A\d{1,10}(?:\.\d{1,4})?\z/) && currency.to_s.match?(/\A[A-Z]{3}\z/)
      raise ArgumentError, 'The supplier did not return a usable quote total.'
    end

    @case.with_lock do
      require_open!
      booking = bookings.find_or_initialize_by(kind: kind, source_id: source)
      raise ArgumentError, 'This offer already has a booking attempt.' unless booking.status.in?(%w[quoted rejected])

      booking.update!(amount: amount, currency: currency, quote: values, status: 'quoted')
    end
    back('Quote saved. Review the total before booking.')
  end

  def book
    booking = bookings.find(params[:booking_id])
    person = traveler(booking.kind)
    @case.with_lock do
      require_open!
      booking.reload
      if bookings.where(kind: booking.kind, status: %w[submitting uncertain]).where.not(id: booking.id).exists?
        raise ArgumentError, 'Resolve the earlier booking attempt for this trip before submitting another.'
      end
      raise ArgumentError, 'Refresh and review a quote before booking.' unless booking.status == 'quoted'
      raise ArgumentError, 'Review and approve the saved amount and currency.' unless params[:approved_total] == "#{booking.amount} #{booking.currency}" &&
        params[:approval] == '1' && params[:quote_version] == booking.updated_at.iso8601(6)
      if booking.kind == 'flight' && Time.iso8601(booking.quote.fetch('expires_at')) <= Time.current
        raise ArgumentError, 'The flight offer expired. Refresh the quote.'
      end
      if booking.kind == 'hotel' && booking.quote['due_at_property'].nil? && params[:acknowledge_fees] != '1'
        raise ArgumentError, 'Acknowledge that mandatory charges at the property may be unknown.'
      end

      booking.update!(status: 'submitting')
    end

    begin
      complete!(booking, supplier.book(booking, person))
    rescue NevaehOs::TravelSupplier::Uncertain
      booking.with_lock { booking.update!(status: 'uncertain') if booking.status == 'submitting' }
      raise
    rescue NevaehOs::TravelSupplier::Unavailable
      booking.with_lock { booking.update!(status: 'rejected') if booking.status == 'submitting' }
      raise
    end
    back('Supplier booking confirmed.')
  end

  def reconcile
    booking = bookings.where(status: %w[submitting uncertain]).find(params[:booking_id])
    complete!(booking, supplier.verify(booking, params.require(:supplier_id)))
    back('Supplier booking verified.')
  end

  private

  def authorize_travel
    response.headers['Cache-Control'] = 'private, no-store'
    return head :forbidden unless NevaehOs::ExecutiveBrief.available_to?(current_user)

    @case = NevaehExecutiveCase.where(owner: current_user, kind: 'travel').find(params[:id])
  end

  def supplier
    @supplier ||= NevaehOs::TravelSupplier.new(current_user, device_ip: request.remote_ip, device_agent: request.user_agent)
  end

  def bookings = NevaehTravelBooking.where(executive_case: @case)

  def require_open!
    raise ArgumentError, 'Reopen the trip in a new work item before booking.' if @case.status == 'closed'
  end

  def traveler(kind)
    keys = %w[given_name family_name email phone_number]
    keys += %w[title gender born_on] if kind == 'flight'
    values = params.require(:travel_person).permit(*keys).to_h.transform_values { |value| value.to_s.strip }
    if keys.any? { |key| !values[key].to_s.length.between?(1, 160) } ||
        !URI::MailTo::EMAIL_REGEXP.match?(values['email']) || !values['phone_number'].match?(/\A\+[1-9]\d{6,14}\z/)
      raise ArgumentError, 'Enter traveler names, an email address, and an international phone number.'
    end
    if kind == 'flight'
      date = Date.iso8601(values['born_on'])
      unless date < Date.current && %w[mr mrs ms miss dr].include?(values['title']) && %w[m f].include?(values['gender'])
        raise ArgumentError, 'Enter the traveler’s date of birth, title, and airline gender marker.'
      end
    end
    values
  rescue Date::Error
    raise ArgumentError, 'Enter a valid date of birth.'
  end

  def complete!(booking, result)
    booking.with_lock do
      if booking.status != 'confirmed'
        booking.update!(**result, status: 'confirmed')
      elsif booking.supplier_id != result.fetch(:supplier_id)
        raise ArgumentError, 'The confirmed supplier record does not match.'
      end
    end
  end

  def back(notice)
    redirect_to dashboard_executive_travel_path(@case), notice: notice, status: :see_other
  end
end
