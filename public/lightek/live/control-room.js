(() => {
  function boot() {
    const room = document.querySelector('.ll-control-room');
    const desk = room?.querySelector('[data-live-desk]');
    if (!desk || desk.dataset.ready) return;

    const tablist = desk.querySelector('[data-live-tabs]');
    const tabs = Array.from(tablist.querySelectorAll('a'));
    const panels = tabs.map(tab => document.getElementById(tab.hash.slice(1)));
    if (panels.some(panel => !panel)) return;
    desk.dataset.ready = 'true';
    tablist.setAttribute('role', 'tablist');
    tabs.forEach((tab, index) => {
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panels[index].id);
      panels[index].setAttribute('role', 'tabpanel');
      panels[index].setAttribute('aria-labelledby', tab.id);
    });

    function select(index) {
      tabs.forEach((tab, position) => {
        const selected = position === index;
        tab.setAttribute('aria-selected', String(selected));
        tab.tabIndex = selected ? 0 : -1;
        panels[position].hidden = !selected;
      });
    }

    function indexForHash(hash) {
      if (!hash) return -1;
      let id;
      try { id = decodeURIComponent(hash.slice(1)); } catch { return -1; }
      const target = document.getElementById(id);
      return target ? panels.findIndex(panel => panel.contains(target)) : -1;
    }

    function showFromHash() {
      const index = indexForHash(location.hash);
      if (index !== -1) select(index);
      else if (!location.hash) select(0);
    }

    function choose(index) {
      select(index);
      if (location.hash !== tabs[index].hash) history.pushState(history.state, '', tabs[index].hash);
    }

    function follow(event) {
      const link = event.target.closest('a[href^="#"]');
      if (!link || event.defaultPrevented || event.button !== 0 ||
          event.metaKey || event.altKey || event.ctrlKey || event.shiftKey) return;
      const index = indexForHash(link.hash);
      if (index === -1) return;
      if (tablist.contains(link)) {
        event.preventDefault();
        choose(index);
      } else {
        select(index);
      }
    }

    function moveTab(event) {
      const current = tabs.indexOf(event.target);
      if (current === -1) return;
      const next = {
        ArrowRight: (current + 1) % tabs.length,
        ArrowLeft: (current + tabs.length - 1) % tabs.length,
        Home: 0,
        End: tabs.length - 1,
        ' ': current
      }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      choose(next);
      tabs[next].focus();
    }

    const destination = room.querySelector('[data-destination]');
    const community = room.querySelector('[data-live-community-fields]');
    const updateDestination = () => {
      community.hidden = !['lightek', 'simulcast'].includes(destination.value);
    };
    destination.addEventListener('change', updateDestination);
    updateDestination();

    room.addEventListener('click', follow);
    tablist.addEventListener('keydown', moveTab);
    window.addEventListener('hashchange', showFromHash);
    select(0);
    showFromHash();

    document.addEventListener('turbo:before-cache', () => {
      delete desk.dataset.ready;
      room.removeEventListener('click', follow);
      tablist.removeEventListener('keydown', moveTab);
      window.removeEventListener('hashchange', showFromHash);
      destination.removeEventListener('change', updateDestination);
    }, { once: true });
  }

  document.addEventListener('turbo:load', boot);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
})();
