(function () {
  function initialize() {
    document.querySelectorAll('[data-mfa-recovery]').forEach(function (panel) {
      var button = panel.querySelector('[data-mfa-recovery-download]');
      var status = panel.querySelector('[data-mfa-recovery-status]');
      if (!button || button.dataset.bound || typeof Blob !== 'function' ||
          typeof URL.createObjectURL !== 'function' || typeof URL.revokeObjectURL !== 'function') return;
      button.dataset.bound = 'true';
      button.hidden = false;
      button.addEventListener('click', function () {
        var codes = Array.from(panel.querySelectorAll('[data-mfa-recovery-codes] code'), function (code) {
          return code.textContent.trim();
        }).filter(Boolean);
        if (!codes.length) return;
        var url;
        var link;
        try {
          var text = 'Lightek recovery codes\n\n' + codes.join('\n') +
            '\n\nKeep this file private. Each code can be used once to verify a sign-in.\n' +
            'Delete codes from your saved copy after using them.\n';
          url = URL.createObjectURL(new Blob([text], {type: 'text/plain;charset=utf-8'}));
          link = document.createElement('a');
          link.href = url;
          link.download = 'lightek-recovery-codes.txt';
          link.hidden = true;
          panel.appendChild(link);
          link.click();
          status.textContent = 'Download requested. Check your downloads and store the file privately before continuing.';
        } catch (_) {
          status.textContent = 'The download could not start. Copy the codes above into your password manager or another safe place.';
        } finally {
          if (link) link.remove();
          // Allow the browser time to consume the file before releasing its URL.
          if (url) setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
        }
      });
    });
  }
  initialize();
  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbo:load', initialize);
})();
