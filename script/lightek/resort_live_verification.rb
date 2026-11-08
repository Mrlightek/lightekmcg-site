# Runs against configured services without changing existing customers' resources.
require 'json'
require 'securerandom'
require 'timeout'
require 'fileutils'
mode, checkout, run_id = ARGV
raise 'Production service credentials required' unless Rails.env.production?
raise 'Invalid verification identity' unless run_id.to_s.match?(/\A\d+\z/)
state_dir = Rails.root.join('tmp/resort-release-verification')
FileUtils.mkdir_p(state_dir, mode: 0o700)
label = "lightek-resort-verify-#{run_id}"
if mode == 'payment'
  key = DymondBank::StripeCredentials.secret_key.to_s
  raise 'Live Stripe configuration required' unless key.start_with?('sk_live_', 'rk_live_')
  Stripe.api_key = key
  file = state_dir.join("payment-#{run_id}.json")
  if file.file?
    saved = JSON.parse(file.read)
    session = Stripe::Checkout::Session.retrieve(saved.fetch('id'))
  else
    session = Stripe::Checkout::Session.create({mode: 'payment',
      line_items: [{price_data: {currency: 'usd', unit_amount: 100, product_data: {name: 'Lightek release verification'}}, quantity: 1}],
      metadata: {lightek_release_verification: run_id},
      success_url: 'https://lightekmcg.com/my/reservations?release_verification=complete',
      cancel_url: 'https://lightekmcg.com/my/reservations', expires_at: 24.hours.from_now.to_i},
      {idempotency_key: "lightek-resort-release-#{run_id}-payment-v1"})
    File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.generate(id: session.id, url: session.url, run_id: run_id)) }
  end
  raise 'Verification checkout mismatch' unless session.metadata.to_h['lightek_release_verification'] == run_id && session.amount_total == 100 && session.currency == 'usd' && session.mode == 'payment'
  puts 'LIGHTEK_LIVE_PAYMENT=' + JSON.generate(status: session.payment_status, amount_cents: 100, live: true, checkout_created: true)
  # This checkout link contains no customer identity, saved card, API credential
  # or bank information. Only the person completing Stripe checkout authorizes a charge.
  puts 'LIGHTEK_VERIFICATION_CHECKOUT_URL=' + session.url.to_s if session.payment_status != 'paid'
  if session.payment_status == 'paid'
    raise 'Payment must have a processor payment intent' unless session.payment_intent.present?
    intent = Stripe::PaymentIntent.retrieve(session.payment_intent)
    raise 'Processor did not confirm the full verification payment' unless intent.status == 'succeeded' && intent.amount_received == 100 && intent.livemode
    puts 'LIGHTEK_LIVE_PAYMENT_VERIFIED=true'
  end
elsif %w[cloud cleanup].include?(mode)
  load File.join(checkout, 'app/services/gatekeeper/compute/providers/linode_adapter.rb')
  provider = ComputeProvider.find_by!(slug: 'linode')
  adapter = provider.adapter(requested_by: "resort-release-verification-#{run_id}")
  tag = 'lightek-release-verification'
  if mode == 'cleanup'
    matches = adapter.nodes.select { |node| node['label'] == label && Array(node['tags']).include?(tag) }
    matches.each { |node| adapter.destroy_node(node.fetch('id')) }
    puts 'LIGHTEK_CLOUD_CLEANUP=' + JSON.generate(matched: matches.size, removed: matches.size)
    exit
  end
  plans = adapter.plans
  base = plans.find { |plan| plan['id'] == 'g6-standard-1' }
  target = plans.find { |plan| plan['id'] == 'g6-standard-2' }
  raise 'Bounded verification plans are unavailable' unless base && target && base.dig('price','monthly').to_f <= 16 && target.dig('price','monthly').to_f <= 32
  raise 'A prior verification allocation needs cleanup' if adapter.nodes.any? { |node| node['label'] == label }
  region = ENV.fetch('LIGHTEK_AUTO_VPS_REGION')
  image = ENV.fetch('LIGHTEK_AUTO_VPS_IMAGE')
  node_id = nil
  receipt = {allocated: false, upgraded: false, downgraded: false, deleted: false}
  wait_for = lambda do |type|
    Timeout.timeout(900) do
      loop do
        state = adapter.node(node_id)
        break state if state['type'] == type && state['status'] == 'running'
        sleep 10
      end
    end
  end
  error = nil
  begin
    node = adapter.provision_node(label: label, region: region, plan: base.fetch('id'), image: image,
      root_password: SecureRandom.urlsafe_base64(36), tags: [tag])
    node_id = node.fetch('id')
    File.open(state_dir.join("cloud-#{run_id}.json"), File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(JSON.generate(id: node_id, label: label, tag: tag)) }
    wait_for.call(base.fetch('id')); receipt[:allocated] = true
    puts 'LIGHTEK_CLOUD_PHASE=allocated'
    adapter.resize_node(node_id, plan: target.fetch('id'))
    wait_for.call(target.fetch('id')); receipt[:upgraded] = true
    puts 'LIGHTEK_CLOUD_PHASE=upgraded'
    adapter.resize_node(node_id, plan: base.fetch('id'))
    wait_for.call(base.fetch('id')); receipt[:downgraded] = true
    puts 'LIGHTEK_CLOUD_PHASE=downgraded'
  rescue StandardError => caught
    error = caught; receipt[:error_class] = caught.class.name
  ensure
    if node_id
      # Never delete an arbitrary ID supplied by a caller or an existing client.
      observed = adapter.node(node_id)
      raise 'Verification cleanup ownership mismatch' unless observed['label'] == label && Array(observed['tags']).include?(tag)
      adapter.destroy_node(node_id); receipt[:deleted] = true
    end
    puts 'LIGHTEK_CLOUD_VERIFICATION=' + JSON.generate(receipt)
  end
  raise error if error
else
  raise 'Unknown verification operation'
end
