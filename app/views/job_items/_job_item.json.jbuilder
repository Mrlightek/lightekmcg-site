json.extract! job_item, :id, :title, :description, :created_at, :updated_at
json.url job_item_url(job_item, format: :json)
