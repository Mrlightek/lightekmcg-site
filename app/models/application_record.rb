class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  before_save { LightekPwa::SourceRuntime.writable! }
  before_destroy { LightekPwa::SourceRuntime.writable! }
end
