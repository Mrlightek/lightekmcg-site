importScripts('/lightek/vendor/omggif/omggif.js');

const width = 480;
const height = 270;
const pixels = width * height;
const palette = Array.from({ length: 256 }, (_, index) => {
  if (index === 0 || index > 216) return 0;
  const n = index - 1;
  return Math.floor(n / 36) * 51 * 65536 + Math.floor(n / 6) % 6 * 51 * 256 + n % 6 * 51;
});
const indices = new Uint8Array(pixels);
let writer, buffer, count, frame;

self.onmessage = ({ data }) => {
  try {
    if (data.type === 'start') {
      count = data.count;
      if (!Number.isInteger(count) || count < 12 || count > 72) throw Error('Invalid GIF duration.');
      buffer = new Uint8Array(count * (pixels * 2 + 1024) + 4096);
      writer = new GifWriter(buffer, width, height, { palette, loop: 0 });
      frame = 0;
    } else {
      if (!writer || data.pixels?.byteLength !== pixels * 4) throw Error('Invalid GIF frame.');
      const rgba = new Uint8ClampedArray(data.pixels);
      for (let i = 0, p = 0; i < pixels; i++, p += 4) {
        indices[i] = rgba[p + 3] < 135 ? 0 :
          1 + Math.round(rgba[p] / 51) * 36 + Math.round(rgba[p + 1] / 51) * 6 + Math.round(rgba[p + 2] / 51);
      }
      const delay = Math.round((frame + 1) * 100 / 12) - Math.round(frame * 100 / 12);
      writer.addFrame(0, 0, width, height, indices, { delay, transparent: 0, disposal: 2 });
      if (++frame === count) {
        const bytes = buffer.slice(0, writer.end()).buffer;
        return self.postMessage({ bytes }, [bytes]);
      }
    }
    self.postMessage({ frame });
  } catch (error) {
    self.postMessage({ error: error.message || 'GIF could not be created.' });
  }
};
