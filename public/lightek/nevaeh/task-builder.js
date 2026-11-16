(() => {
  function boot() {
    document.querySelectorAll('[data-task-builder]').forEach(form => {
      if (form.dataset.builderReady) return;
      form.dataset.builderReady = 'true';
      form.querySelectorAll('[data-builder-fixed]').forEach(fixed => {
        const expected = Array.from(form.querySelectorAll('[data-builder-expected]')).find(row => row.dataset.builderExpected === fixed.dataset.builderFixed);
        if (!expected) return;
        const input = expected.querySelector('input');
        const update = () => {
          const variable = fixed.value.trim() === '';
          expected.hidden = !variable;
          input.disabled = !variable;
          input.required = variable;
        };
        fixed.addEventListener('input', update);
        update();
      });
    });
  }
  document.addEventListener('DOMContentLoaded', boot);
  document.addEventListener('turbo:load', boot);
  boot();
})();
