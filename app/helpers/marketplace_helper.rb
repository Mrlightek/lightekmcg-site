module MarketplaceHelper
  def marketplace_optional_page_path(name)
    return unless %i[about contact].include?(name.to_sym)
    route = Rails.application.routes.named_routes[name.to_sym]
    return unless route && route.required_parts.empty?
    main_app.public_send("#{name}_path")
  end
  def marketplace_money(cents, currency)
    Money.new(Integer(cents), currency.to_s).format
  end
  def marketplace_checkout_url(offer, interval)
    dymond_bank.checkout_path(slug: offer.slug, interval: interval)
  end
  def marketplace_rate(listing)
    offer = listing.offer
    if listing.configuration.to_h["billing"] == "both"
      monthly = DymondBank::Checkout.preview(offer: offer, interval: "monthly")
      annual = DymondBank::Checkout.preview(offer: offer, interval: "annual")
      return safe_join([
        content_tag(:span, safe_join([marketplace_money(monthly[:recurring_cents], offer.currency), content_tag(:small, " / month")]), class: "lm-rate-option"),
        content_tag(:span, safe_join([marketplace_money(annual[:recurring_cents], offer.currency), content_tag(:small, " / year")]), class: "lm-rate-option")
      ])
    end
    preview = DymondBank::Checkout.preview(offer: offer, interval: offer.default_interval)
    return "Unavailable" unless preview[:ok]
    recurring = preview[:recurring_cents].to_i
    if recurring.positive?
      "#{marketplace_money(recurring, offer.currency)} / #{offer.default_interval.to_s == 'annual' ? 'year' : 'month'}"
    elsif preview[:setup_fee_cents].to_i.positive?
      "#{marketplace_money(preview[:setup_fee_cents], offer.currency)} once"
    else
      "Free"
    end
  end
end
