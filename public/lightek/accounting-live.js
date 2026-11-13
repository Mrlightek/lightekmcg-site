(() => {
  if (window.lightekAccountingLive) return;
  window.lightekAccountingLive = true;
  function bind() {
    document.querySelectorAll("form[data-accounting-reconciliation]").forEach(form => {
      if (form.dataset.liveBound) return;
      form.dataset.liveBound = "true";
      const feedback = form.querySelector("[data-reconciliation-feedback]");
      let timer, counter = 0, pending;
      const currency = new Intl.NumberFormat(undefined, {style: "currency", currency: "USD"});
      async function preview() {
        const ticket = ++counter;
        pending?.abort();
        pending = new AbortController();
        const values = new FormData(form);
        values.set("finalize", "0");
        if (!["starts_on", "ends_on", "starting_amount", "ending_amount"].every(key => values.get(key))) return;
        feedback.textContent = "Checking reconciliation…";
        try {
          const response = await fetch(form.action, {method: "POST", body: values, credentials: "same-origin", signal: pending.signal,
            headers: {Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""}});
          if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("Reverify sign-in or use Check live proof to continue.");
          const proof = await response.json();
          if (ticket !== counter) return;
          if (!response.ok) throw new Error(proof.error || "Proof could not be checked.");
          const a = Number(proof.cleared_difference_cents), b = Number(proof.book_difference_cents);
          if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b)) throw new Error("Proof needs review.");
          feedback.textContent = `Cleared difference ${currency.format(a / 100)} · Book difference ${currency.format(b / 100)}. ${a === 0 && b === 0 ? "Both proofs balance." : "Discrepancy: review balances and cleared items."}`;
          feedback.setAttribute("role", a === 0 && b === 0 ? "status" : "alert");
        } catch (error) {
          if (error.name !== "AbortError" && ticket === counter) feedback.textContent = error.message;
        }
      }
      const changed = () => { clearTimeout(timer); timer = setTimeout(preview, 600); };
      form.addEventListener("input", changed);
      form.addEventListener("change", changed);
    });
  }
  document.addEventListener("turbo:load", bind);
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", bind) : bind();
})();
