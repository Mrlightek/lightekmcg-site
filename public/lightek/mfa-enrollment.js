(function () {
  function initialize() {
    document.querySelectorAll('[data-mfa-enrollment]').forEach(function (panel) {
      if (panel.dataset.ready === 'true') return;
      var status = panel.querySelector('[data-mfa-qr-status]');
      var manual = panel.querySelector('[data-mfa-manual]');
      try {
        if (typeof window.qrcode !== 'function') throw new Error('Encoder unavailable');
        var qr = window.qrcode(0, 'M');
        qr.addData(panel.dataset.mfaEnrollment, 'Byte');
        qr.make();
        var modules = qr.getModuleCount();
        var quiet = 4;
        var scale = 6;
        var canvas = panel.querySelector('[data-mfa-qr]');
        canvas.width = canvas.height = (modules + quiet * 2) * scale;
        var context = canvas.getContext('2d');
        context.fillStyle = '#ffffff';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.fillStyle = '#000000';
        for (var row = 0; row < modules; row++) {
          for (var col = 0; col < modules; col++) {
            if (qr.isDark(row, col)) context.fillRect((col + quiet) * scale, (row + quiet) * scale, scale, scale);
          }
        }
        canvas.hidden = false;
        status.textContent = 'Scan this code with your phone’s authenticator app.';
        panel.dataset.ready = 'true';
      } catch (_) {
        status.textContent = 'The QR code could not load. Use the manual setup key below.';
        manual.open = true;
      }
      var copy = panel.querySelector('[data-mfa-copy]');
      if (copy && !copy.dataset.bound) {
        copy.dataset.bound = 'true';
        copy.addEventListener('click', async function () {
          var key = panel.querySelector('[data-mfa-setup-key]');
          try {
            await navigator.clipboard.writeText(key.value);
            copy.textContent = 'Setup key copied';
          } catch (_) {
            key.focus();
            key.select();
            copy.textContent = 'Select and copy the setup key';
          }
        });
      }
    });
  }
  initialize();
  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbo:load', initialize);
})();
