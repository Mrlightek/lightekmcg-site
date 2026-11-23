(() => {
  const input = document.querySelector("[data-contact-suggestions-url]");
  const suggestions = document.querySelector("[data-contact-suggestions]");
  if (!input || !suggestions || input.dataset.contactsInitialized) return;
  input.dataset.contactsInitialized = "true";

  let timer;
  let request;
  const currentQuery = () => input.value.split(",").at(-1).trim();
  const hide = () => {
    suggestions.replaceChildren();
    suggestions.hidden = true;
  };
  const stop = () => {
    clearTimeout(timer);
    request?.abort();
    hide();
  };

  const render = (contacts) => {
    if (contacts.length === 0) return;
    const list = document.createElement("ul");
    for (const { name, email } of contacts) {
      const item = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "secondary";
      button.textContent = name ? `${name} · ${email}` : email;
      button.addEventListener("mousedown", (event) => event.preventDefault());
      button.addEventListener("click", () => {
        const recipients = input.value.split(",").slice(0, -1).map((value) => value.trim()).filter(Boolean);
        if (!recipients.some((value) => value.toLowerCase() === email.toLowerCase())) recipients.push(email);
        input.value = recipients.join(", ");
        stop();
        input.focus();
      });
      item.append(button);
      list.append(item);
    }
    suggestions.replaceChildren(list);
    suggestions.hidden = false;
  };

  input.addEventListener("input", () => {
    stop();
    const query = currentQuery();
    if (query.length < 2) return;
    timer = setTimeout(async () => {
      const pending = new AbortController();
      request = pending;
      const url = new URL(input.dataset.contactSuggestionsUrl, window.location.origin);
      url.searchParams.set("q", query);
      try {
        const response = await fetch(url, { headers: { Accept: "application/json" }, signal: pending.signal });
        if (!response.ok) return;
        const contacts = await response.json();
        if (!pending.signal.aborted && currentQuery() === query) render(contacts);
      } catch {
        if (!pending.signal.aborted) hide();
      }
    }, 180);
  });

  input.addEventListener("keydown", (event) => {
    if (event.key === "Escape") stop();
    const first = suggestions.querySelector("button");
    if (event.key === "ArrowDown" && first) {
      event.preventDefault();
      first.focus();
    }
  });
  suggestions.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      stop();
      input.focus();
    }
  });
  for (const element of [input, suggestions]) {
    element.addEventListener("focusout", (event) => {
      if (event.relatedTarget !== input && !suggestions.contains(event.relatedTarget)) stop();
    });
  }
})();
