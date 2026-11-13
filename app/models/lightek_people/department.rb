module LightekPeople
  class Department < ApplicationRecord
    self.table_name = 'lightek_people_departments'
    belongs_to :employer, class_name: 'User'
    belongs_to :parent, class_name: name, optional: true
    has_many :employments, dependent: :restrict_with_exception
    validates :name, :code, presence: true, length: {maximum: 100}
    validates :code, uniqueness: {scope: :employer_id}
    before_validation { self.code = code.to_s.strip.upcase }
    validate :parent_is_local_and_acyclic
    private
    def parent_is_local_and_acyclic
      seen = [id].compact
      node = parent
      while node
        if node.employer_id != employer_id || seen.include?(node.id)
          errors.add(:parent, 'must belong to this employer without a reporting cycle')
          break
        end
        seen << node.id
        node = node.parent
      end
    end
  end
end
