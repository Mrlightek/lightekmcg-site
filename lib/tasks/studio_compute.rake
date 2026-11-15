namespace :studio do
  namespace :cpu do
    desc "Mark expired CPU attempts failed so authorized users can resume them"
    task reconcile: :environment do
      Studio::Compute::Lease.reconcile!(StudioOperation.all)
      puts "Expired CPU attempts reconciled; no new renders or charges created."
    end
  end
end
