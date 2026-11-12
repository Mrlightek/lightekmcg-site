require_relative 'session_rooms_checks'
require ROOT.join('app/services/lightek_sessions/room_creation').to_s
require ROOT.join('app/controllers/dashboard/rooms_controller').to_s
Dashboard::RoomsController.layout 'reservations'
class ProductionLivePreviewController < ApplicationController
  def index
    @site = DymondSite::Site.find(params[:site_id])
    @encoder_ready = false; @restream_ready = false; @tiktok_ready = false
    @communities = []; @stage_assets = []; @library_assets = []; @recent = []
    @session_rooms = LightekSessions::Room.joins(:resource).where(lightek_reservation_resources: {site_id: @site.id}).includes(:resource)
    @restream_chat_url = nil
    @audience_connections = {tiktok: 'lightek_test', ssn: false, restream: false}
    render template: 'dashboard/live_broadcasts/index', layout: 'reservations'
  end
end
class ProductionRoomsChecks < SessionRoomsChecks
  SessionRoomsChecks.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def create_room(**attributes)
    LightekSessions::RoomCreation.call(site: @site, actor: @owner,
      attributes: {name: 'Lightek conversation', kind: 'video', duration_minutes: 60, capacity: 2}.merge(attributes))
  end
  def test_private_room_has_no_fake_booking_or_order_and_is_not_in_catalog
    bookings = LightekReservations::Reservation.count
    orders = LightekCommerce::Order.count
    room = create_room
    assert room.production?
    assert_equal @owner.id, room.host_user_id
    refute room.resource.published?
    assert_nil room.resource.product_id
    assert_equal bookings, LightekReservations::Reservation.count
    assert_equal orders, LightekCommerce::Order.count
    assert_equal 0, room.bookings.count
    refute LightekReservations::Resource.available.exists?(id: room.resource_id)
  end
  def test_invited_guest_waits_for_admission_and_cannot_invite_others
    room = create_room
    member = LightekSessions::Access.invite!(room, @owner, @guest.email_address)
    assert_nil member.reservation_id
    assert LightekSessions::Access.authorize!(room, @guest)
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest, joining: true) }
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.invite!(room, @guest, @other.email_address) }
    room.update!(status: 'open');member.update!(status: 'admitted')
    assert LightekSessions::Access.authorize!(room, @guest, joining: true)
    member.update!(status: 'blocked')
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest) }
  end
  def test_private_room_capacity_and_cross_site_ownership_are_enforced
    room = create_room(capacity: 1)
    LightekSessions::Access.invite!(room, @owner, @guest.email_address)
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.invite!(room, @owner, @other.email_address) }
    assert_raises(LightekSessions::Access::Denied) do
      LightekSessions::RoomCreation.call(site: @site, actor: @other, attributes: {name: 'Foreign room'})
    end
    assert_raises(ArgumentError) { create_room(kind: 'server') }
    assert_raises(ArgumentError) { create_room(capacity: 1000) }
  end
  def test_direct_room_create_redirects_to_a_real_room_and_renders_invite_and_setup
    post '/dashboard/rooms', params: {site_id: @site.id, room: {name: 'My interview', kind: 'voice', capacity: 3, duration_minutes: 60}}, headers: as(@owner)
    assert_response :see_other
    room = LightekSessions::Room.order(:id).last
    assert room.production?
    assert_equal 'voice', room.resource.kind
    follow_redirect!(headers: as(@owner));assert_response :success
    assert_includes response.body, 'Invite a guest'
    assert_includes response.body, 'Set up room service'
    assert_includes response.body, 'Copy room link'
    assert_includes response.body, "site_id=#{@site.id}"
  end
  def test_client_site_owner_can_create_rooms_and_bookable_resources
    @owner.update!(role: 'client')
    post '/dashboard/rooms', params: {site_id: @site.id, room: {name: 'Client room', kind: 'video'}}, headers: as(@owner)
    assert_response :see_other
    post '/dashboard/reservations/experiences', params: {site_id: @site.id, resource: {name: 'Book my video room', kind: 'video', timezone: 'America/New_York', capacity: 4, duration_minutes: 30, published: '1'}}, headers: as(@owner)
    assert_response :redirect
    resource = LightekReservations::Resource.find_by!(name: 'Book my video room')
    assert resource.native_session?
    assert resource.published?
  end
  def test_failed_resource_save_keeps_the_form_and_errors
    post '/dashboard/reservations/experiences', params: {site_id: @site.id, resource: {name: 'Keep this name', kind: 'video', timezone: 'America/New_York', capacity: 0, duration_minutes: 30}}, headers: as(@owner)
    assert_response :unprocessable_entity
    assert_includes response.body, 'Keep this name'
    assert_includes response.body, 'Check these details'
    assert_includes response.body, 'Capacity'
  end
  def test_room_creation_errors_keep_entered_name
    post '/dashboard/rooms', params: {site_id: @site.id, room: {name: 'Keep my room', kind: 'video', capacity: 0}}, headers: as(@owner)
    assert_response :unprocessable_entity
    assert_includes response.body, 'Keep my room'
    assert_includes response.body, 'guest places'
  end
  def test_production_room_schedule_and_end_are_enforced
    room = create_room(starts_at: 1.hour.from_now.iso8601)
    member = LightekSessions::Access.invite!(room, @owner, @guest.email_address)
    member.update!(status: 'admitted');room.update!(status: 'open')
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest, joining: true) }
    room.update!(ends_at: 1.minute.ago)
    assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest) }
  end
  def test_bookable_room_can_be_created_reserved_and_opened_without_external_url
    post '/dashboard/reservations/experiences', params: {site_id: @site.id, resource: {name: 'Book this conversation', kind: 'video', timezone: 'America/New_York', capacity: 4, duration_minutes: 30, published: '1'}}, headers: as(@owner)
    assert_response :redirect
    resource = LightekReservations::Resource.find_by!(name: 'Book this conversation')
    post '/my/reservations', params: {resource_id: resource.id, starts_at: 2.hours.from_now.iso8601, checkout_key: SecureRandom.uuid}, headers: as(@guest)
    assert_response :redirect
    booking = resource.reservations.sole
    assert_equal 'confirmed', booking.status
    assert_nil booking.order_id
    post reservation_session_room_path(booking), headers: as(@guest)
    assert_response :see_other
    room = LightekSessions::Room.find_by!(resource: resource)
    assert_equal 'booking', room.purpose
  end
  def test_one_time_service_price_still_requires_verified_payment_before_room_access
    priced = LightekCommerce::Product.create!(site: @site, name: 'Paid consultation', slug: SecureRandom.hex(8), published: true, price_cents: 5000, inventory_quantity: 10, product_type: 'service', billing_interval: 'one_time')
    resource = LightekReservations::Resource.create!(site: @site, name: 'Paid room', kind: 'video', published: true, product: priced, notice_minutes: 0)
    post '/my/reservations', params: {resource_id: resource.id, starts_at: 2.hours.from_now.iso8601, checkout_key: SecureRandom.uuid}, headers: as(@guest)
    assert_response :redirect
    booking = resource.reservations.sole
    assert_equal 'held', booking.status
    assert_equal 5000, booking.order.total_cents
    post reservation_session_room_path(booking), headers: as(@guest)
    assert_response :forbidden
  end
  def test_private_room_resource_cannot_be_published_through_booking_editor
    room = create_room
    assert_raises(ActiveRecord::RecordNotFound) do
      post '/dashboard/reservations/experiences', params: {site_id: @site.id, id: room.resource_id, resource: {published: '1'}}, headers: as(@owner)
    end
    refute room.resource.reload.published?
  end
  def test_workflow_templates_render_and_keep_website_context
    room = create_room
    previews = {}
    get '/dashboard/rooms', params: {site_id: @site.id}, headers: as(@owner)
    assert_response :success;assert_includes response.body, 'Create a room';previews['rooms'] = response.body
    get '/dashboard/reservations', params: {site_id: @site.id}, headers: as(@owner)
    assert_response :success;assert_includes response.body, 'Create a bookable room';previews['reservations'] = response.body
    get '/preview/live', params: {site_id: @site.id, session_room: room.key}, headers: as(@owner)
    assert_response :success
    assert_includes response.body, 'data-stage-preset="split"'
    assert_includes response.body, 'Audience desk'
    assert_includes response.body, '@lightek_test'
    assert_includes response.body, "/dashboard/live?site_id=#{@site.id}"
    previews['live'] = response.body
    get session_room_path(room.key), headers: as(@owner);assert_response :success;previews['room'] = response.body
    if ENV['PRODUCTION_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['PRODUCTION_PREVIEW_DIR'])
      previews.each { |name, html| File.write(File.join(ENV['PRODUCTION_PREVIEW_DIR'], name + '.html'), html) }
    end
  end

end
