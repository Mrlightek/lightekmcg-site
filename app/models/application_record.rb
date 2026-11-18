class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  before_save { LightekPwa::SourceRuntime.writable!(record: self) }
  before_destroy { LightekPwa::SourceRuntime.writable!(record: self) }
end
