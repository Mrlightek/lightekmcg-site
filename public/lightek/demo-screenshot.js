(() => {
  const initialized = new WeakSet();

  async function capture(form) {
    const button = form.querySelector('[data-capture-start]');
    const input = form.querySelector('[data-capture-file]');
    const status = form.querySelector('[data-capture-status]');
    const video = document.createElement('video');
    video.muted = true;
    video.playsInline = true;
    let stream;
    button.disabled = true;
    status.textContent = 'Choose the product demo window or tab.';
    try {
      stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
      if (stream.getVideoTracks()[0]?.getSettings().displaySurface === 'monitor') {
        status.textContent = 'Select a demo window or browser tab instead of the entire screen.';
        return;
      }
      video.srcObject = stream;
      await video.play();
      const canvas = document.createElement('canvas');
      const scale = Math.min(1, 1600 / video.videoWidth, 1600 / video.videoHeight);
      canvas.width = Math.round(video.videoWidth * scale);
      canvas.height = Math.round(video.videoHeight * scale);
      canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      const screenshot = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
      if (!screenshot || screenshot.size > 5 * 1024 * 1024) throw new Error('Invalid screenshot');
      const files = new DataTransfer();
      files.items.add(new File([screenshot], 'demo-screenshot.png', { type: 'image/png' }));
      input.files = files.files;
      status.textContent = 'Screenshot captured. Save it to review it in the walkthrough.';
    } catch {
      status.textContent = 'Capture did not finish. Try again or choose a PNG screenshot.';
    } finally {
      stream?.getTracks().forEach(track => track.stop());
      video.srcObject = null;
      button.disabled = false;
    }
  }

  function start() {
    if (!navigator.mediaDevices?.getDisplayMedia || typeof DataTransfer === 'undefined') return;
    document.querySelectorAll('[data-demo-capture]').forEach(form => {
      if (initialized.has(form)) return;
      initialized.add(form);
      const button = form.querySelector('[data-capture-start]');
      button.hidden = false;
      button.addEventListener('click', () => capture(form));
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
  document.addEventListener('turbo:load', start);
})();
