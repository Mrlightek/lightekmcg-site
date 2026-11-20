document.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-copy-x-dm]");
  if (!button) return;

  const draft = button.closest("[data-x-dm-draft]");
  const message = draft.querySelector("[data-x-dm-text]");
  const status = draft.querySelector("[data-x-dm-status]");
  const text = message.value;

  if (!text.trim()) {
    status.textContent = "Write a message to copy.";
    message.focus();
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
    status.textContent = "Draft copied. Paste it into X to review and send.";
  } catch {
    message.focus();
    message.select();
    status.textContent = "Draft selected. Use your browser’s Copy command, then paste it into X.";
  }
});
