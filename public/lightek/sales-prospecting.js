document.addEventListener("click", async (event) => {
  const addStep = event.target.closest("[data-add-cadence-step]");
  if (addStep) {
    const form = addStep.form;
    const steps = form.querySelector("[data-cadence-steps]");
    const step = form.querySelector("[data-cadence-step-template]").content.cloneNode(true);
    const input = step.querySelector("input");
    steps.append(step);
    addStep.disabled = steps.children.length >= 20;
    input.focus();
    return;
  }

  const removeStep = event.target.closest("[data-remove-cadence-step]");
  if (removeStep) {
    const addButton = removeStep.form.querySelector("[data-add-cadence-step]");
    removeStep.closest("[data-cadence-step]").remove();
    addButton.disabled = false;
    addButton.focus();
    return;
  }

  const button = event.target.closest("button[data-copy-prospect-draft]");
  if (!button) return;

  const draft = button.closest("[data-prospect-draft]");
  const message = draft.querySelector("[data-prospect-draft-text]");
  const status = draft.querySelector("[data-prospect-draft-status]");
  const text = message.value;

  if (!text.trim()) {
    status.textContent = "Write a message to copy.";
    message.focus();
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
    status.textContent = "Draft copied. Paste it into the conversation to review and send.";
  } catch {
    message.focus();
    message.select();
    status.textContent = "Draft selected. Use your browser’s Copy command, then paste it into the conversation.";
  }
});
