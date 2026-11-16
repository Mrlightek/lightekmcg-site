# Run after migrations and Rails/worker restart, on the deployed host:
# LIGHTEK_RUN_RUNTIME_REPORT_ACCEPTANCE=1 LIGHTEK_ACCEPTANCE_ACTOR_ID=1 bin/rails runner script/lightek/nevaeh_runtime_report_acceptance.rb
abort 'Set LIGHTEK_RUN_RUNTIME_REPORT_ACCEPTANCE=1 for the isolated live journal test' unless ENV['LIGHTEK_RUN_RUNTIME_REPORT_ACCEPTANCE']=='1'
actor=User.find(Integer(ENV.fetch('LIGHTEK_ACCEPTANCE_ACTOR_ID')))
receipt=NevaehOs::RuntimeReportAcceptance.new(actor:actor).run!
root=Rails.root.join('storage','nevaeh_acceptance')
NevaehOs::ReportJournal.directories!(root)
path=root.join("#{receipt.fetch(:downstream_task_id)}.json")
File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0600) do |file|
  file.write(JSON.pretty_generate(receipt)+"\n");file.flush;file.fsync
end
puts JSON.generate(receipt.merge(receipt_path:path.to_s))
