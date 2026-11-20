importScripts('/lightek/vendor/omggif/omggif.js');

self.onmessage = ({ data }) => {
  try {
    const gif = new GifReader(new Uint8Array(data));
    const { width, height } = gif;
    const count = gif.numFrames();
    const size = width * height;
    if (!size || width > 640 || height > 640 || !count || count > 150 || size * count > 12000000) {
      throw Error('Use a GIF up to 640 pixels per side with fewer or smaller frames.');
    }
    const pixels = new Uint8ClampedArray(size * 4);
    let elapsed = 0;
    const frames = [];
    for (let i = 0; i < count; i++) {
      const frame = gif.frameInfo(i);
      const { x, y, width: w, height: h } = frame;
      if (!w || !h || x + w > width || y + h > height) throw Error('GIF frame extends outside the image.');
      const previous = frame.disposal === 3 ? pixels.slice() : null;
      gif.decodeAndBlitFrameRGBA(i, pixels);
      elapsed += Math.max(40, frame.delay * 10);
      frames.push({ pixels: pixels.slice().buffer, end: elapsed });
      if (previous) pixels.set(previous);
      if (frame.disposal === 2) {
        for (let row = y; row < y + h; row++) {
          pixels.fill(0, (row * width + x) * 4, (row * width + x + w) * 4);
        }
      }
    }
    self.postMessage({ width, height, frames, duration: elapsed }, frames.map(frame => frame.pixels));
  } catch (error) {
    self.postMessage({ error: error.message || 'GIF could not be decoded.' });
  }
};
