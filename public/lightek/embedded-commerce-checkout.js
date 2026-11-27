(() => {
  async function mountCheckout() {
    const checkout = document.querySelector("[data-embedded-checkout]");
    if (!checkout || checkout.dataset.checkoutMounted) return;
    checkout.dataset.checkoutMounted = "true";
    const status = checkout.querySelector("[data-checkout-status]");

    try {
      const clientSecret = checkout.dataset.checkoutSecret;
      delete checkout.dataset.checkoutSecret;
      const stripe = window.Stripe(checkout.dataset.publishableKey);
      const page = await stripe.createEmbeddedCheckoutPage({
        fetchClientSecret: async () => clientSecret,
        onComplete: () => window.location.assign(checkout.dataset.completionUrl),
      });
      page.mount(checkout.querySelector("[data-checkout-form]"));
      status.hidden = true;
      document.addEventListener("turbo:before-cache", () => page.destroy(), { once: true });
    } catch {
      status.textContent = "Secure checkout could not load. Reload this page to try again.";
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountCheckout);
  } else {
    mountCheckout();
  }
  document.addEventListener("turbo:load", mountCheckout);
})();
