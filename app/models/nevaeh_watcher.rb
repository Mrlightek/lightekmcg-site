# frozen_string_literal: true
class NevaehWatcher < ApplicationRecord
  belongs_to :user
  belongs_to :nevaeh_os_agent
  has_many :events,class_name:'NevaehWatchEvent',dependent: :restrict_with_error
  KINDS=%w[ubuntu_package ubuntu_catalog ubuntu_sources github_repository github_account].freeze
  validates :name,presence:true,length:{maximum:160}
  validates :kind,inclusion:{in:KINDS}
  validates :condition,inclusion:{in:%w[new updated new_or_updated]}
  validates :response,inclusion:{in:%w[prepare update command]}
  validates :status,inclusion:{in:%w[active paused]}
  validates :interval_minutes,numericality:{only_integer:true,greater_than_or_equal_to:5,less_than_or_equal_to:525600}
  validate do
    errors.add(:nevaeh_os_agent,'belongs to another account') if nevaeh_os_agent && nevaeh_os_agent.user_id!=user_id
    NevaehOs::WatchContract.validate!(kind:kind,target:target,response:response,template:command_template)
  rescue ArgumentError => error
    errors.add(:base,error.message)
  end
  before_save do
    if persisted? && (will_save_change_to_kind? || will_save_change_to_target? || will_save_change_to_condition? || will_save_change_to_response? || will_save_change_to_command_template? || will_save_change_to_nevaeh_os_agent_id?)
      self.baseline={};self.initialized=false;self.lease_token=nil;self.lease_expires_at=nil
    end
    if status!='active'
      self.next_poll_at=nil;self.lease_token=nil;self.lease_expires_at=nil
    elsif next_poll_at.nil? || will_save_change_to_interval_minutes? || will_save_change_to_status?
      self.next_poll_at=Time.current
    end
  end
end
