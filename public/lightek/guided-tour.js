(() => {
  if (window.lightekGuidedTourLoaded) return;
  window.lightekGuidedTourLoaded = true;

  const seen = new Set();
  let active, paused, scheduled;

  function account(shell) {
    if (shell.dataset.tourApp !== "pwa") return shell.dataset.tourAccount;
    const identity = window.LightekIdentity;
    return identity?.authenticated && identity.id;
  }

  function available(element) {
    if (!element || element.closest("[hidden]") || getComputedStyle(element).visibility === "hidden") return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && rect.right > 0 && rect.left < document.documentElement.clientWidth;
  }

  function context(scope, user) {
    const steps = Array.from(document.querySelectorAll("[data-tour-step]"))
      .filter(marker => marker.dataset.tourStep === scope)
      .map(marker => ({
        marker, target: available(marker) ? marker : marker.dataset.tourFallback && document.querySelector(marker.dataset.tourFallback)
      }))
      .filter(step => available(step.target));
    return { key: `lightek:guided-tour:v1:${user}:${scope}`, steps };
  }

  function hasSeen(key) {
    try { return seen.has(key) || localStorage.getItem(key) === "seen"; }
    catch { return seen.has(key); }
  }

  function remember(key) {
    seen.add(key);
    try { localStorage.setItem(key, "seen"); } catch { /* Some browsers block storage. */ }
  }

  function resumeStep(key) {
    if (paused?.key === key) return paused.index;
    try {
      const saved = sessionStorage.getItem(`${key}:paused`);
      return saved === null ? null : Number(saved);
    } catch { return null; }
  }

  function close({ resume = false, focus = true } = {}) {
    if (!active) return;
    const { dialog, step, tour, index, trigger } = active;
    active = null;
    paused = resume ? { key: tour.key, index } : null;
    try {
      if (resume) sessionStorage.setItem(`${tour.key}:paused`, String(index));
      else sessionStorage.removeItem(`${tour.key}:paused`);
    } catch { /* The current page can still resume the tour. */ }
    dialog.close();
    dialog.remove();
    trigger.textContent = resume ? "Resume tour" : "Take a tour";
    if (focus) {
      const control = resume && step?.marker.hasAttribute("data-tour-try")
        ? step.target.querySelector("input:not([type=hidden]), select, textarea, a[href], button") || step.target
        : trigger;
      control.focus({ preventScroll: true });
    }
  }

  function position() {
    if (!active?.step) return;
    const { dialog, step } = active;
    const width = document.documentElement.clientWidth;
    const height = document.documentElement.clientHeight;
    const rect = step.target.getBoundingClientRect();
    const panel = dialog.getBoundingClientRect();
    const gap = 16;
    const clamp = (value, max) => Math.max(gap, Math.min(value, max - gap));
    const left = Math.max(0, rect.left - 5);
    const top = Math.max(0, rect.top - 5);
    const right = Math.min(width, rect.right + 5);
    const bottom = Math.min(height, rect.bottom + 5);
    const spot = dialog.querySelector("[data-tour-spotlight]");
    spot.hidden = right <= left || bottom <= top;
    dialog.dataset.hasSpotlight = String(!spot.hidden);
    Object.assign(spot.style, { left: `${left}px`, top: `${top}px`, width: `${right-left}px`, height: `${bottom-top}px` });

    let x = rect.left, y = bottom + gap;
    if (y + panel.height + gap > height) {
      if (top - panel.height - gap >= gap) y = top - panel.height - gap;
      else if (right + panel.width + 2 * gap <= width) { x = right + gap; y = top; }
      else if (left - panel.width - 2 * gap >= 0) { x = left - panel.width - gap; y = top; }
      else y = height - panel.height - gap;
    }
    dialog.style.left = `${clamp(x, width - panel.width)}px`;
    dialog.style.top = `${clamp(y, height - panel.height)}px`;
  }

  function showStep(index) {
    const { dialog, tour } = active;
    active.index = index;
    const step = tour.steps[index];
    active.step = step;
    const rect = step.target.getBoundingClientRect();
    if (rect.top < 70 || rect.bottom > document.documentElement.clientHeight - 16) {
      step.target.scrollIntoView({ block: "center", inline: "nearest" });
    }
    const heading = dialog.querySelector("#lightek-tour-title");
    heading.textContent = step.marker.dataset.tourTitle;
    dialog.querySelector("#lightek-tour-body").textContent = step.marker.dataset.tourBody;
    dialog.querySelector("[data-tour-count]").textContent = `${index + 1} of ${tour.steps.length}`;
    dialog.querySelector("[data-tour-back]").disabled = index === 0;
    dialog.querySelector("[data-tour-next]").textContent = index === tour.steps.length - 1 ? "Finish" : "Next";
    dialog.querySelector("[data-tour-practice]").hidden = !step.marker.hasAttribute("data-tour-try");
    position();
    heading.focus({ preventScroll: true });
  }

  function open(tour, trigger, index = 0) {
    if (active || !tour.steps.length || document.querySelector("dialog[open]")) return;
    const dialog = document.createElement("dialog");
    dialog.className = "lightek-tour";
    dialog.setAttribute("aria-labelledby", "lightek-tour-title");
    dialog.setAttribute("aria-describedby", "lightek-tour-body");
    dialog.innerHTML = `
      <div class="lightek-tour-spotlight" data-tour-spotlight aria-hidden="true" hidden></div>
      <div class="lightek-tour-panel">
        <div class="lightek-tour-header">
          <span data-tour-count></span>
          <button type="button" data-tour-skip>Skip tour</button>
        </div>
        <h2 id="lightek-tour-title" tabindex="-1"></h2>
        <p id="lightek-tour-body"></p>
        <div class="lightek-tour-actions">
          <button type="button" data-tour-back>Back</button>
          <button type="button" data-tour-practice hidden>Try it</button>
          <button type="button" class="lightek-tour-next" data-tour-next>Next</button>
        </div>
      </div>`;
    document.body.append(dialog);
    active = { dialog, tour, trigger };
    remember(tour.key);
    dialog.addEventListener("cancel", event => { event.preventDefault(); close(); });
    dialog.querySelector("[data-tour-skip]").onclick = () => close();
    dialog.querySelector("[data-tour-practice]").onclick = () => close({ resume: true });
    dialog.querySelector("[data-tour-back]").onclick = () => showStep(active.index - 1);
    dialog.querySelector("[data-tour-next]").onclick = () => {
      if (active.index + 1 === tour.steps.length) close();
      else showStep(active.index + 1);
    };
    dialog.showModal();
    showStep(Number.isInteger(index) && index >= 0 && index < tour.steps.length ? index : 0);
  }

  function initialize() {
    const shell = document.querySelector("[data-tour-app]");
    const trigger = shell?.querySelector("[data-tour-open]");
    const user = shell && account(shell);
    if (!trigger || !user || typeof HTMLDialogElement === "undefined" || !HTMLDialogElement.prototype.showModal) return;
    const page = shell.querySelector("[data-tour-page]");
    const appScope = shell.dataset.tourApp;
    const pageScope = page?.dataset.tourPage;
    const preferredScope = pageScope || appScope;
    const preferred = context(preferredScope, user);
    const primary = preferred.steps.length ? preferredScope : appScope;
    const manual = primary === preferredScope ? preferred : context(primary, user);
    trigger.hidden = !manual.steps.length;
    trigger.textContent = resumeStep(manual.key) === null ? "Take a tour" : "Resume tour";
    trigger.onclick = () => {
      const tour = context(primary, user);
      open(tour, trigger, resumeStep(tour.key) ?? 0);
    };

    const autoScope = page?.hasAttribute("data-tour-auto") ? preferredScope : appScope;
    if (!shell.hasAttribute("data-tour-quiet")) {
      const tour = context(autoScope, user);
      if (!hasSeen(tour.key)) open(tour, trigger);
    }
  }

  function schedule() {
    cancelAnimationFrame(scheduled);
    scheduled = requestAnimationFrame(initialize);
  }

  document.addEventListener("DOMContentLoaded", schedule);
  document.addEventListener("turbo:load", schedule);
  document.addEventListener("turbo:before-cache", () => {
    cancelAnimationFrame(scheduled);
    close({ focus: false });
  });
  window.addEventListener("lightek.bootstrap.ready", schedule);
  window.addEventListener("pageshow", schedule);
  window.addEventListener("hashchange", () => close({ focus: false }));
  window.addEventListener("resize", position);
  window.addEventListener("scroll", position, { capture: true, passive: true });
  schedule();
})();
