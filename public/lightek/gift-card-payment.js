(() => {
  function mount() {
    const form = document.querySelector("[data-gift-payment]");
    if (!form || form.dataset.mounted) return;

    form.dataset.mounted = "true";
    const status = form.querySelector("[data-payment-result]");
    const button = form.querySelector("button[type='submit']");
    const clientSecret = form.dataset.clientSecret;
    const returnURL = form.dataset.returnUrl;
    delete form.dataset.clientSecret;

    try {
      const stripe = window.Stripe(form.dataset.publishableKey);
      const elements = stripe.elements({ clientSecret });
      const payment = elements.create("payment");
      payment.mount(form.querySelector("[data-payment-element]"));
      payment.on("ready", () => {
        status.textContent = "";
        button.disabled = false;
      });
      payment.on("loaderror", () => {
        status.textContent = "Secure payment could not load. Reload this page to retry.";
      });
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        button.disabled = true;
        try {
          const result = await stripe.confirmPayment({
            elements, confirmParams: { return_url: returnURL }, redirect: "if_required"
          });
          if (result.error) throw result.error;
          window.location.assign(returnURL);
        } catch (error) {
          status.textContent = error.message || "Payment could not be confirmed. Please retry.";
          button.disabled = false;
        }
      });
      document.addEventListener("turbo:before-cache", () => payment.destroy(), { once: true });
    } catch {
      status.textContent = "Secure payment could not load. Reload this page to retry.";
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
  document.addEventListener("turbo:load", mount);
})();
