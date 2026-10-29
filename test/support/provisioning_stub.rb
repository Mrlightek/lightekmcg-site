# frozen_string_literal: true
# Minimal method stubs for the existing Rails tests when minitest/mock is unavailable.
# Restore the original method (including visibility) after the block.
module LightekProvisioningStub
  def stub(name, replacement)
    singleton = singleton_class
    existed = singleton.method_defined?(name) || singleton.private_method_defined?(name) || singleton.protected_method_defined?(name)
    visibility = if singleton.private_method_defined?(name)
      :private
    elsif singleton.protected_method_defined?(name)
      :protected
    else
      :public
    end
    original = singleton.instance_method(name) if existed
    singleton.define_method(name) do |*args, **kwargs, &block|
      if replacement.respond_to?(:call)
        replacement.call(*args, **kwargs, &block)
      else
        replacement
      end
    end
    singleton.send(visibility, name)
    yield
  ensure
    if existed && original
      singleton.define_method(name, original)
      singleton.send(visibility, name)
    else
      singleton.remove_method(name) if singleton.instance_methods(false).include?(name) ||
        singleton.private_instance_methods(false).include?(name) ||
        singleton.protected_instance_methods(false).include?(name)
    end
  end
end

Object.include(LightekProvisioningStub)
