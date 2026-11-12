/* Keep the workstation in Dashboard; expanding it is an explicit local choice. */
(() => {
  const host = document.querySelector('#lightek-studio-dashboard');
  const button = host?.querySelector('[data-studio-focus]');
  if (!button) return;
  const ribbon = button.closest('.business-workspace');
  let previousOverflow;
  function focus(expanded) {
    host.classList.toggle('studio-focus-expanded', expanded);
    button.setAttribute('aria-pressed', String(expanded));
    button.textContent = expanded ? 'Exit focus mode' : 'Focus mode';
    if (expanded) { previousOverflow = document.documentElement.style.overflow; document.documentElement.style.overflow = 'hidden'; }
    else { document.documentElement.style.overflow = previousOverflow ?? ''; button.focus(); }
    window.dispatchEvent(new Event('resize'));
  }
  button.addEventListener('click', () => focus(!host.classList.contains('studio-focus-expanded')));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && host.classList.contains('studio-focus-expanded')) { event.preventDefault(); focus(false); }
  });
  new ResizeObserver(() => host.style.setProperty('--studio-context-height', `${ribbon.getBoundingClientRect().height}px`)).observe(ribbon);
})();
