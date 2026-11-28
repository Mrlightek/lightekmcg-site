(() => {
  const FLAG = '__lightekOrderViews';
  if (window[FLAG]) return;
  window[FLAG] = true;

  const fields = ['status', 'from', 'through'];
  const initialized = new WeakSet();

  function setup() {
    document.querySelectorAll('[data-saved-order-views]').forEach(panel => {
      if (initialized.has(panel)) return;
      initialized.add(panel);

      const filters = panel.closest('.dd-panel').querySelector('[data-order-filters]');
      const save = panel.querySelector('[data-order-view-save]');
      const name = save.elements.namedItem('view_name');
      const picker = panel.querySelector('[data-order-view-picker]');
      const apply = panel.querySelector('[data-order-view-apply]');
      const remove = panel.querySelector('[data-order-view-remove]');
      const message = panel.querySelector('[data-order-view-message]');
      const key = `lightek:order-views:v1:${panel.dataset.savedOrderViews}`;

      const read = () => {
        const views = JSON.parse(localStorage.getItem(key) || '[]');
        return Array.isArray(views) ? views.filter(view => typeof view?.name === 'string' && view.filters) : [];
      };
      const refresh = views => {
        picker.replaceChildren(...views.map((view, index) => new Option(view.name, String(index))));
        picker.disabled = apply.disabled = remove.disabled = views.length === 0;
      };
      const saveViews = (views, notice) => {
        localStorage.setItem(key, JSON.stringify(views));
        refresh(views);
        message.textContent = notice;
      };
      const handle = action => {
        try {
          action();
        } catch (_) {
          message.textContent = 'Saved views are unavailable in this browser.';
        }
      };

      handle(() => refresh(read()));
      panel.hidden = false;
      save.addEventListener('submit', event => {
        event.preventDefault();
        handle(() => {
          const title = name.value.trim();
          if (!title) {
            message.textContent = 'Enter a name for this view.';
            return;
          }
          const selected = Object.fromEntries(fields.map(field => [field, filters.elements.namedItem(field).value]));
          const views = read();
          if (views.some(view => view.name.toLowerCase() === title.toLowerCase())) {
            message.textContent = 'A view with that name already exists.';
            return;
          }
          if (views.length >= 20) {
            message.textContent = 'Remove a saved view before adding another.';
            return;
          }
          saveViews([...views, {name: title, filters: selected}], 'Order view saved.');
          picker.value = String(views.length);
          name.value = '';
        });
      });
      apply.addEventListener('click', () => handle(() => {
        const view = read()[Number(picker.value)];
        if (!view) return;
        fields.forEach(field => { filters.elements.namedItem(field).value = view.filters[field] || ''; });
        filters.elements.namedItem('lookup').value = '';
        filters.requestSubmit();
      }));
      remove.addEventListener('click', () => handle(() => {
        const views = read();
        const index = Number(picker.value);
        if (!views[index]) return;
        views.splice(index, 1);
        saveViews(views, 'Order view removed.');
      }));
    });
  }

  document.addEventListener('DOMContentLoaded', setup);
  document.addEventListener('turbo:load', setup);
  setup();
})();
