module StudioLiveTestSupport
  # Minitest 6 no longer bundles minitest/mock. Keep these tests dependency-free.
  def with_live_stub(object, name, value)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs| value }
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end
end
ActiveSupport::TestCase.include(StudioLiveTestSupport)
