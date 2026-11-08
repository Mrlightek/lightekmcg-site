(() => {
  document.querySelectorAll('[data-reservation-slots]').forEach(form => {
    const input = form.querySelector('[name="starts_at"]');
    const output = form.querySelector('[data-slots-output]');
    if (!input || !output) return;
    let request;
    input.addEventListener('change', async () => {
      if (!input.value) return;
      if (request) request.abort();
      request = new AbortController();
      const date = input.value.slice(0, 10);
      const url = new URL('/reservations/slots', location.origin);
      url.searchParams.set('date', date);
      url.searchParams.set('resource_id', form.querySelector('[name="resource_id"]').value);
      url.searchParams.set('site_id', form.querySelector('[name="site_id"]').value);
      output.textContent = 'Checking available times…';
      try {
        const response = await fetch(url, {signal: request.signal, headers: {Accept: 'application/json'}});
        if (!response.ok) throw Error('Unavailable');
        const data = await response.json();
        output.replaceChildren();
        if (!data.slots.length) output.textContent = 'No open times on this date.';
        data.slots.forEach(slot => {
          const button = document.createElement('button'); button.type = 'button';
          button.textContent = new Intl.DateTimeFormat('en-US', {hour: 'numeric', minute: '2-digit', timeZone: data.timezone}).format(new Date(slot));
          button.addEventListener('click', () => {
            // An explicit offset preserves the selected instant through DST.
            let hidden = form.querySelector('[data-selected-slot]');
            if (!hidden) { hidden = document.createElement('input'); hidden.type = 'hidden'; hidden.name = 'starts_at'; hidden.dataset.selectedSlot = ''; form.append(hidden); }
            input.removeAttribute('name'); hidden.value = slot;
            input.value = new Intl.DateTimeFormat('sv-SE', {timeZone: data.timezone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false}).format(new Date(slot)).replace(' ', 'T');
          });
          output.append(button);
        });
      } catch (error) { if (error.name !== 'AbortError') output.textContent = 'Availability will be checked when you reserve.'; }
    });
    input.addEventListener('input', () => {
      form.querySelector('[data-selected-slot]')?.remove(); input.name = 'starts_at';
    });
  });
})();
