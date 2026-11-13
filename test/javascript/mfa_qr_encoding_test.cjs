const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const jsQR = require('jsqr');
const root = path.resolve(__dirname, '../..');
const html = fs.readFileSync(path.join(process.env.MFA_QR_CAPTURE_DIR, 'enroll.html'), 'utf8');
const script = fs.readFileSync(path.join(root, 'public/lightek/mfa-enrollment.js'), 'utf8');
const encoder = fs.readFileSync(path.join(root, 'public/lightek/vendor/qrcode-generator/qrcode.js'), 'utf8');
function windowFor() {
  const dom = new JSDOM(html, {runScripts: 'outside-only', url: 'https://example.test/identity/security/enroll'});
  dom.window.HTMLCanvasElement.prototype.getContext = function () {
    this.pixels = new Uint8ClampedArray(this.width * this.height * 4);
    const canvas = this;
    return {fillStyle: '#fff', fillRect(x, y, width, height) {
      const color = this.fillStyle === '#000000' ? 0 : 255;
      for (let row = y; row < y + height; row++) for (let col = x; col < x + width; col++) {
        const index = (row * canvas.width + col) * 4;
        canvas.pixels.set([color, color, color, 255], index);
      }
    }};
  };
  return dom;
}
const dom = windowFor();
dom.window.eval(encoder);
dom.window.eval(script);
const panel = dom.window.document.querySelector('[data-mfa-enrollment]');
const canvas = panel.querySelector('[data-mfa-qr]');
assert.equal(panel.dataset.ready, 'true');
const decoded = jsQR(canvas.pixels, canvas.width, canvas.height, {inversionAttempts: 'dontInvert'});
assert(decoded, 'The actual canvas drawing must produce a decodable QR');
assert.equal(decoded.data, panel.dataset.mfaEnrollment);
const uri = new URL(decoded.data);
assert.equal(uri.protocol, 'otpauth:');
assert.equal(uri.hostname, 'totp');
assert.equal(uri.searchParams.get('secret'), panel.querySelector('[data-mfa-setup-key]').value);
assert.equal(uri.searchParams.get('issuer'), 'Lightek');
assert.equal(uri.searchParams.get('digits'), '6');
assert.equal(uri.searchParams.get('period'), '30');
assert.equal(uri.searchParams.get('algorithm'), 'SHA1');
assert.equal(canvas.hidden, false);
assert.equal(panel.querySelector('[data-mfa-manual]').open, false);
dom.window.close();
const fallback = windowFor();
fallback.window.eval(script);
assert.equal(fallback.window.document.querySelector('[data-mfa-manual]').open, true);
assert.match(fallback.window.document.querySelector('[data-mfa-qr-status]').textContent, /manual setup key/);
fallback.window.close();
console.log('MFA_QR_ENCODING_PASS: actual Rails setup secret and full TOTP URI independently decoded from canvas output; fallback passes');
