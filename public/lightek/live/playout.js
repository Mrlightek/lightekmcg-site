(() => {
  function setupRundown() {
    const form = document.querySelector('[data-rundown-editor]');
    if (!form || form.dataset.initialized) return;
    form.dataset.initialized = 'true';
    const rows = form.querySelector('[data-rundown-rows]');
    const template = form.querySelector('[data-rundown-row]');
    const add = form.querySelector('[data-add-row]');

    const breakTypes = ["pre_roll", "mid_roll", "pre_end_roll"];

    function refresh() {
      const fields = Array.from(rows.children);
      fields.forEach((row, index) => {
        const kind = row.querySelector('[data-field="kind"]').value;
        const commercial = breakTypes.includes(kind);
        const external = row.querySelector('[data-external-slot]');
        external.hidden = !commercial || !!row.querySelector('[data-field="ad_campaign_id"]')?.value;
        external.querySelector('input').disabled = external.hidden;
        const addSlot = row.querySelector('[data-add-slot]');
        addSlot.hidden = !commercial;
        addSlot.disabled = fields.length >= 40;
        row.querySelector('legend').textContent = (commercial ? 'Commercial slot ' : 'Row ') + (index + 1);
        row.querySelector('[data-move="up"]').disabled = index === 0;
        row.querySelector('[data-move="down"]').disabled = index === fields.length - 1;
        row.querySelector('[data-remove-row]').disabled = fields.length === 1;
        row.querySelectorAll('[data-field]').forEach(input => {
          input.name = 'airing[rows][' + index + '][' + input.dataset.field + ']';
        });
      });
      add.disabled = fields.length >= 40;
    }

    const listeners = new AbortController();
    document.addEventListener('turbo:before-cache', () => listeners.abort(), { once: true });
    add.addEventListener('click', () => {
      rows.append(template.content.cloneNode(true));
      refresh();
      rows.lastElementChild.querySelector('select').focus();
    }, { signal: listeners.signal });

    rows.addEventListener('change', refresh, { signal: listeners.signal });
    rows.addEventListener('click', event => {
      const button = event.target.closest('button');
      if (!button || button.disabled) return;
      const row = button.closest('fieldset');
      if (button.hasAttribute('data-add-slot')) {
        const slot = template.content.firstElementChild.cloneNode(true);
        slot.querySelector('[data-field="kind"]').value = row.querySelector('[data-field="kind"]').value;
        const external = row.querySelector('[data-field="external_ad"]');
        slot.querySelector('[data-field="external_ad"]').checked = !external.disabled && external.checked;
        row.after(slot);
        slot.querySelector('[data-field="asset_id"]').focus();
      } else if (button.hasAttribute('data-remove-row')) {
        const neighbor = row.nextElementSibling || row.previousElementSibling;
        row.remove();
        neighbor.querySelector('select').focus();
      } else if (button.dataset.move === 'up') {
        rows.insertBefore(row, row.previousElementSibling);
      } else if (button.dataset.move === 'down') {
        rows.insertBefore(row.nextElementSibling, row);
      }
      refresh();
    }, { signal: listeners.signal });

    if (!rows.firstElementChild) rows.append(template.content.cloneNode(true));
    refresh();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setupRundown, { once: true });
  else setupRundown();
  document.addEventListener('turbo:load', setupRundown);
  document.addEventListener('turbo:before-cache', () => {
    const form = document.querySelector('[data-rundown-editor]');
    if (form) delete form.dataset.initialized;
  });
})();
