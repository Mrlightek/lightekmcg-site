(() => {
  function setupRundown() {
    const form = document.querySelector('[data-rundown-editor]');
    if (!form || form.dataset.initialized) return;
    form.dataset.initialized = 'true';
    const rows = form.querySelector('[data-rundown-rows]');
    const template = form.querySelector('[data-rundown-row]');
    const add = form.querySelector('[data-add-row]');

    function refresh() {
      const fields = Array.from(rows.children);
      fields.forEach((row, index) => {
        row.querySelector('legend').textContent = 'Row ' + (index + 1);
        row.querySelector('[data-move="up"]').disabled = index === 0;
        row.querySelector('[data-move="down"]').disabled = index === fields.length - 1;
        row.querySelector('[data-remove-row]').disabled = fields.length === 1;
        row.querySelectorAll('[data-field]').forEach(input => {
          input.name = 'airing[rows][' + index + '][' + input.dataset.field + ']';
        });
      });
      add.disabled = fields.length >= 40;
    }

    add.addEventListener('click', () => {
      rows.append(template.content.cloneNode(true));
      refresh();
      rows.lastElementChild.querySelector('select').focus();
    });

    rows.addEventListener('click', event => {
      const button = event.target.closest('button');
      if (!button || button.disabled) return;
      const row = button.closest('fieldset');
      if (button.hasAttribute('data-remove-row')) {
        const neighbor = row.nextElementSibling || row.previousElementSibling;
        row.remove();
        neighbor.querySelector('select').focus();
      } else if (button.dataset.move === 'up') {
        rows.insertBefore(row, row.previousElementSibling);
      } else if (button.dataset.move === 'down') {
        rows.insertBefore(row.nextElementSibling, row);
      }
      refresh();
    });

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
