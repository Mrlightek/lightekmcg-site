function copySelection(source) {
  source.focus();
  source.select();
  try {
    return document.execCommand?.("copy") === true;
  } catch {
    return false;
  }
}

document.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-use-server-name], button[data-copy-server-name]");
  if (!button) return;

  const form = button.form;
  const source = form.querySelector("[data-server-name-source]");
  const confirmation = form.querySelector("[data-server-name-confirmation]");
  const status = form.querySelector("[data-server-name-status]");

  if (button.hasAttribute("data-use-server-name")) {
    confirmation.value = source.value;
    confirmation.focus();
    status.textContent = "Server name filled in.";
    return;
  }

  let copied = false;
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(source.value);
      copied = true;
    } catch {
      copied = copySelection(source);
    }
  } else {
    copied = copySelection(source);
  }

  status.textContent = copied
    ? "Server name copied."
    : "Name selected. Copy it with your browser, or choose Use server name.";
});
