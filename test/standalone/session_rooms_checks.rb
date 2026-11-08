require_relative 'reservations_http_checks'
require 'base64'
require 'openssl'
require ROOT.join('app/services/gatekeeper/studio_live_policy').to_s
module LightekVault
  class Service
    class AccessDenied < StandardError; end
    class << self; attr_accessor :secrets; end
    self.secrets = {}
    def self.store!(slug:, payload:, **) = secrets[slug] = payload.deep_dup
    def self.checkout!(slug:, **) = secrets.fetch(slug).deep_dup
  end
end
path = ROOT.join('db/migrate/20261109000000_create_lightek_session_rooms.rb')
eval(path.read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]"), TOPLEVEL_BINDING, path.to_s)
CreateLightekSessionRooms.new.migrate(:up)
path = ROOT.join('db/migrate/20261109003000_add_session_presentation.rb')
eval(path.read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]"), TOPLEVEL_BINDING, path.to_s)
AddSessionPresentation.new.migrate(:up)
%w[models/lightek_sessions/room models/lightek_sessions/member services/lightek_sessions/access services/lightek_sessions/presentation services/lightek_sessions/media services/studio/live/audience jobs/lightek_sessions/close_room_job jobs/lightek_sessions/retire_media_room_job controllers/session_rooms_controller].each { |file| require ROOT.join("app/#{file}").to_s }
module SessionCleanup
  def setup
    LightekSessions::Member.delete_all
    LightekSessions::Room.delete_all
    super
  end
end
ReservationsChecks.prepend(SessionCleanup)
ApplicationController.helper(Module.new { def dashboard_live_path(**) = '/dashboard/live' })
class SessionRoomsChecks < ActionDispatch::IntegrationTest
  def app = ReservationHarness
  def setup
    fixtures = ReservationsChecks.new('unused'); fixtures.setup
    @owner, @guest, @other, @site = %i[owner guest other site].map { |key| fixtures.instance_variable_get("@#{key}") }
    @resource = fixtures.resource(capacity: 4)
    @start = Time.current.change(sec: 0) + 5.minutes
    @booking = fixtures.reserve(resource: @resource, start: @start, quantity: 2)
    @room = LightekSessions::Room.for_reservation!(@booking)
    host! 'example.test'
    LightekVault::Service.secrets['session-media-'+@site.id.to_s] = {'url'=>'wss://media.example.test/rtc', 'api_key'=>'test-key', 'api_secret'=>'test-secret'}
  end
  def as(user) = {'X-Test-User'=>user.id.to_s}
  def decode(token) = JSON.parse(Base64.urlsafe_decode64(token.split('.')[1]))
  def admitted
    @room.update!(status: 'open')
    LightekSessions::Access.request!(@room,@guest).update!(status:'admitted')
  end
  def test_slot_shares_a_room_but_rescheduled_reservation_does_not
    assert_equal @room.id, LightekSessions::Room.for_reservation!(@booking).id
    @booking.update!(starts_at: @start + 1.day, ends_at: @booking.ends_at + 1.day)
    refute_equal @room.id, LightekSessions::Room.for_reservation!(@booking).id
    assert_raises(LightekSessions::Access::Denied){ LightekSessions::Access.authorize!(@room,@guest) }
  end
  def test_stranger_and_admin_from_another_site_cannot_join_or_control
    get session_room_path(@room.key),headers:as(@other);assert_response :forbidden
    post session_room_control_path(@room.key),params:{operation:'open'},headers:as(@guest),as: :json;assert_response :forbidden
  end
  def test_unpaid_and_canceled_reservations_fail_closed
    @booking.update!(status:'held');assert_raises(LightekSessions::Access::Denied){ LightekSessions::Access.authorize!(@room,@guest) }
    @booking.update!(status:'canceled');post reservation_session_room_path(@booking),headers:as(@guest);assert_response :forbidden
  end
  def test_owner_renders_host_desk_and_guest_gets_no_host_controls
    get session_room_path(@room.key),headers:as(@owner);assert_response :success;assert_includes response.body,'Host desk'
    get session_room_path(@room.key),headers:as(@guest);assert_response :success;refute_includes response.body,'data-control="open"'
  end
  def test_lobby_and_admission_require_a_valid_reservation
    get session_room_state_path(@room.key),headers:as(@guest);assert_response :success;refute JSON.parse(response.body)['admitted']
    post session_room_ticket_path(@room.key),params:{consent:true},headers:as(@guest),as: :json;assert_response :forbidden
    post session_room_control_path(@room.key),params:{operation:'open'},headers:as(@owner),as: :json;assert_response :success
    member = @room.members.find_by!(user:@guest)
    post session_room_control_path(@room.key),params:{operation:'admit',member_id:member.id},headers:as(@owner),as: :json;assert_response :success
    @booking.update!(status:'canceled')
    post session_room_ticket_path(@room.key),params:{consent:true},headers:as(@guest),as: :json;assert_response :forbidden
  end
  def test_media_tokens_are_short_lived_room_scoped_and_not_admin
    admitted
    media=LightekSessions::Media.new(@site)
    media.stub(:call,{}) do
      result=media.join!(@room,@guest); token=decode(result[:token])
      assert_equal @room.media_name,token.dig('video','room')
      assert_equal true,token.dig('video','canPublish')
      refute token.dig('video','roomAdmin');refute token.dig('video','roomCreate')
      assert_operator token['exp']-Time.current.to_i,:<=,45
      segments=result[:token].split('.');actual=Base64.urlsafe_decode64(segments[2]);assert_equal OpenSSL::HMAC.digest('SHA256','test-secret',segments.first(2).join('.')),actual
      refute_includes result.to_json,'test-secret'
    end
  end
  def test_voice_restricts_camera_and_live_audience_cannot_publish
    admitted
    media=LightekSessions::Media.new(@site)
    media.stub(:call,{}) do
      @resource.update!(kind:'voice');@room.reload;assert_equal ['microphone'],decode(media.join!(@room,@guest)[:token]).dig('video','canPublishSources')
      @resource.update!(kind:'live');@room.reload;refute decode(media.join!(@room,@guest)[:token]).dig('video','canPublish')
      assert decode(media.join!(@room,@owner)[:token]).dig('video','canPublish')
    end
  end
  def test_studio_source_is_host_only_and_cannot_publish_media
    admitted
    media=LightekSessions::Media.new(@site)
    media.stub(:call,{}) do
      assert_raises(LightekSessions::Access::Denied){media.join!(@room,@guest,studio:true)}
      token=decode(media.join!(@room,@owner,studio:true)[:token]);assert_equal "user-#{@owner.id}-studio",token['sub'];refute token.dig('video','canPublish');refute token.dig('video','canPublishData')
    end
  end
  def test_time_window_lock_and_ended_room_revoke_new_tickets
    admitted
    assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.authorize!(@room,@guest,now:@start-16.minutes,joining:true)}
    @room.update!(locked:true);assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.authorize!(@room,@guest,joining:true)}
    assert LightekSessions::Access.authorize!(@room,@owner,joining:true)
    @room.update!(status:'ended');assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.authorize!(@room,@owner,joining:true)}
  end
  def test_guest_invites_consume_only_the_purchased_places
    member=LightekSessions::Access.invite!(@room,@guest,@other.email_address);assert_equal @booking.id,member.reservation_id
    extra=User.create!(email_address:'extra@example.test',role:'client')
    assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.invite!(@room,@guest,extra.email_address)}
    assert LightekSessions::Access.authorize!(@room,@other)
    @booking.update!(status:'canceled');assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.authorize!(@room,@other)}
  end
  def test_removing_a_guest_rotates_the_provider_room_before_retiring_old_access
    admitted
    old_name=@room.media_name
    member=@room.members.find_by!(user:@guest)
    post session_room_control_path(@room.key),params:{operation:'remove',member_id:member.id},headers:as(@owner),as: :json
    assert_response :success
    assert_equal 'blocked',member.reload.status
    refute_equal old_name,@room.reload.media_name
    assert_includes LightekSessions::RetireMediaRoomJob.enqueues,[@room.id,old_name]
    assert_raises(LightekSessions::Access::Denied){LightekSessions::Access.authorize!(@room,@guest)}
  end
  def test_ticket_requires_explicit_broadcast_consent
    admitted
    post session_room_ticket_path(@room.key),params:{},headers:as(@guest),as: :json;assert_response :forbidden
  end
  def test_external_links_are_preserved_and_server_booking_cannot_become_room
    @resource.update!(join_url:'https://example.test/meeting')
    assert_raises(LightekSessions::Access::Denied){LightekSessions::Room.for_reservation!(@booking)}
    @resource.update!(join_url:nil,kind:'service');refute @resource.native_session?
  end
  def test_chat_embed_does_not_accept_arbitrary_iframes_or_credentials
    valid='https://chat.restream.io/embed?token=read-only-example'
    assert_equal valid,Studio::Live::Audience.validate_chat_url!(valid)
    ['https://evil.example/embed?token=x','javascript:alert(1)','https://chat.restream.io.evil.example/embed?a=1','https://user:pass@chat.restream.io/embed?token=x','http://chat.restream.io/embed?token=x'].each do |url|
      assert_raises(ArgumentError){Studio::Live::Audience.validate_chat_url!(url)}
    end
  end
  def test_presentation_persists_only_for_host_and_validates_render_settings
    values={layout:'presenter',title:'Boardroom live',background:'#142f2c',accent:'#d6edac',participants:{"user-#{@guest.id}"=>{name:'Guest speaker',effect:'mono'}}}
    patch session_room_presentation_path(@room.key),params:{presentation:values},headers:as(@guest),as: :json;assert_response :forbidden
    patch session_room_presentation_path(@room.key),params:{presentation:values},headers:as(@owner),as: :json;assert_response :success
    assert_equal 'presenter',@room.reload.presentation['layout']
    assert_equal 'mono',@room.presentation.dig('participants',"user-#{@guest.id}",'effect')
    values[:background]='url(https://evil.example)'
    patch session_room_presentation_path(@room.key),params:{presentation:values},headers:as(@owner),as: :json;assert_response :unprocessable_entity
    assert_equal '#142f2c',@room.reload.presentation['background']
  end
  def test_social_username_and_session_settings_are_validated_without_overwriting_stream_keys
    Studio::Live::Audience.stub(:settings,{}) do
      Gatekeeper::StudioLivePolicy.stub(:authorize!,true) do
        Studio::Live::Audience.save!(user:@guest,tiktok_username:'@test.creator')
        assert_equal 'test.creator',LightekVault::Service.secrets.fetch("studio-audience-#{@guest.id}")['tiktok_username']
        assert_raises(ArgumentError){Studio::Live::Audience.save!(user:@guest,tiktok_username:'https://tiktok.com/@bad')}
        assert_raises(ArgumentError){Studio::Live::Audience.save!(user:@guest,ssn_session:'../../etc/passwd')}
      end
    end
  end
  def test_chat_embed_is_separate_from_streaming_credentials
    Studio::Live::Audience.stub(:settings,{}) do
    Gatekeeper::StudioLivePolicy.stub(:authorize!,true) do
      Studio::Live::Audience.save!(user:@guest,chat_url:'https://chat.restream.io/embed?token=example')
    end
    end
    stored=LightekVault::Service.secrets.fetch("studio-audience-#{@guest.id}")
    assert_equal ['chat_url'],stored.keys
    assert_equal 'https://chat.restream.io/embed?token=example',stored['chat_url']
  end
end
