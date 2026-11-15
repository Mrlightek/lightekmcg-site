require Rails.root.join("lib/middleware/studio_cpu_request_limit")
Rails.application.config.middleware.insert_before 0, StudioCpuRequestLimit
