const currency = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });

function filterList(root, kind) {
  const search = root.querySelector(`[data-workspace-search="${kind}"]`);
  const query = search.value.trim().toLowerCase();
  const items = kind === "chat"
    ? root.querySelector("[data-workspace-thread]:not([hidden])").querySelectorAll("[data-workspace-chat-message], li")
    : root.querySelector('[data-workspace-list="mail"]').children;
  let matches = 0;
  for (const item of items) {
    item.hidden = !item.textContent.toLowerCase().includes(query);
    if (!item.hidden) matches += 1;
  }
  root.querySelector(`[data-workspace-empty="${kind}"]`).hidden = matches > 0;
}

function updateBudget(root) {
  const fields = Array.from(root.querySelectorAll("[data-workspace-number]"));
  const total = fields.every(field => field.value !== "" && field.validity.valid)
    ? currency.format(fields[0].valueAsNumber * fields[1].valueAsNumber)
    : "Enter valid hours and rate";
  root.querySelector('[data-workspace-output="budget"]').textContent = total;
}

document.addEventListener("input", event => {
  const input = event.target;
  const root = input.closest("[data-workspace-preview]");
  if (!root) return;

  if (input.matches("[data-workspace-search]")) filterList(root, input.dataset.workspaceSearch);
  if (input.matches("[data-workspace-number]")) updateBudget(root);
  if (input.matches("[data-workspace-document]")) root.querySelector('[data-workspace-status="document"]').textContent = "";
});

document.addEventListener("change", event => {
  const input = event.target;
  const root = input.closest("[data-workspace-preview]");
  if (!root) return;

  if (input.matches("[data-workspace-option]")) {
    root.querySelector(`[data-workspace-output="${input.dataset.workspaceOption}"]`).textContent = input.value;
  }
  if (input.matches("[data-workspace-drive]")) {
    for (const folder of root.querySelectorAll("[data-workspace-folder]")) {
      folder.hidden = folder.dataset.workspaceFolder !== input.value;
    }
  }
  if (input.matches("[data-workspace-channel]")) {
    for (const thread of root.querySelectorAll("[data-workspace-thread]")) {
      thread.hidden = thread.dataset.workspaceThread !== input.value;
    }
    root.querySelector("[data-workspace-reply]").value = "";
    root.querySelector('[data-workspace-status="chat"]').textContent = "";
    root.querySelector('[data-workspace-search="chat"]').value = "";
    filterList(root, "chat");
  }
});

document.addEventListener("click", event => {
  const button = event.target.closest("button");
  const root = button?.closest("[data-workspace-preview]");
  if (!root) return;

  if (button.matches("[data-workspace-restore]")) {
    const documentInput = root.querySelector("[data-workspace-document]");
    documentInput.value = documentInput.defaultValue;
    root.querySelector('[data-workspace-status="document"]').textContent = "Sample draft restored.";
  }
  if (button.matches("[data-workspace-slide-button]")) {
    const [first, second] = root.querySelectorAll("[data-workspace-slide]");
    const showingFirst = first.hidden;
    first.hidden = !showingFirst;
    second.hidden = showingFirst;
    button.textContent = showingFirst ? "Next slide" : "Previous slide";
    root.querySelector('[data-workspace-output="slide-count"]').textContent = showingFirst ? "1 of 2" : "2 of 2";
  }
  if (button.matches("[data-workspace-post]")) {
    const reply = root.querySelector("[data-workspace-reply]");
    const body = reply.value.trim();
    if (!body) {
      reply.focus();
      return;
    }
    const item = document.createElement("li");
    item.textContent = `You · ${body}`;
    root.querySelector("[data-workspace-thread]:not([hidden]) [data-workspace-list]").append(item);
    reply.value = "";
    root.querySelector('[data-workspace-search="chat"]').value = "";
    filterList(root, "chat");
    root.querySelector('[data-workspace-status="chat"]').textContent = "Sample reply added.";
  }
});
