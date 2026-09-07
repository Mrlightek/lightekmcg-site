FactoryBot.define do
  factory :system_job do
    name { "MyString" }
    priority { 1 }
    job_item { nil }
  end
end
