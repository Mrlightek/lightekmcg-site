const transitions = {
  stage: ["review", "Draft staged. Review the sample destination and draft before publishing."],
  review: ["publish", "Draft revision reviewed. You can now publish this sample release."],
  publish: ["restore", "Sample release published. Try restoring the previous theme."],
  restore: ["stage", "Previous sample theme restored. You can run the practice again."]
};

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-release-action]");
  if (!button || button.disabled) return;

  const practice = button.closest("[data-demo-release-practice]");
  const transition = transitions[button.dataset.releaseAction];
  if (!practice || !transition) return;

  const [next, message] = transition;
  practice.querySelector("[data-release-status]").textContent = message;
  practice.querySelectorAll("[data-release-action]").forEach((control) => {
    control.disabled = control.dataset.releaseAction !== next;
    if (!control.disabled) control.focus();
  });
});
