document.addEventListener("input", event => {
  const input = event.target.closest("[data-demo-input]");
  const preview = input?.closest("[data-agency-preview]");
  if (!preview) return;
  const key = input.dataset.demoInput;
  if (key === "theme") {
    preview.querySelector("[data-demo-canvas]").dataset.theme = input.value;
    return;
  }
  const output = [...preview.querySelectorAll("[data-demo-output]")].find(node => node.dataset.demoOutput === key);
  if (output) output.textContent = input.value;
});
