const assert = require("node:assert/strict");
const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    const evidence = await page.evaluate(async () => {
      const canvas = document.createElement("canvas");
      canvas.width = 160;
      canvas.height = 90;
      document.body.appendChild(canvas);
      const context = canvas.getContext("2d");
      let frames = 0;
      const redraw = () => {
        context.fillStyle = frames++ % 2 ? "#3874bc" : "#d78027";
        context.fillRect(0, 0, 160, 90);
      };
      redraw();
      const stream = canvas.captureStream(12);
      const timer = setInterval(redraw, 80);
      const recorder = new MediaRecorder(stream, { mimeType: "video/webm" });
      const chunks = [];
      recorder.ondataavailable = event => chunks.push(event.data);
      try {
        await new Promise((resolve, reject) => {
          recorder.onstop = resolve;
          recorder.onerror = reject;
          recorder.start();
          setTimeout(() => recorder.stop(), 600);
        });
        const blob = new Blob(chunks, { type: "video/webm" });
        const url = URL.createObjectURL(blob);
        try {
          const video = document.createElement("video");
          video.muted = true;
          video.src = url;
          document.body.appendChild(video);
          await video.play();
          await new Promise(resolve => video.requestVideoFrameCallback(resolve));
          return { width: video.videoWidth, height: video.videoHeight, bytes: blob.size };
        } finally {
          URL.revokeObjectURL(url);
        }
      } finally {
        clearInterval(timer);
        stream.getTracks().forEach(track => track.stop());
      }
    });
    assert.equal(evidence.width, 160);
    assert.equal(evidence.height, 90);
    assert(evidence.bytes > 0);
    console.log(JSON.stringify({ scenario: "synthetic_browser_webm_codec", ...evidence }));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
