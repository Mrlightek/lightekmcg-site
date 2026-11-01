export class WebcamSource {
  constructor() { this.stream = null; this.generation = 0; }
  async open() {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error('Webcam capture requires HTTPS and a supported browser.');
    this.close(); const generation = this.generation;
    const stream = await navigator.mediaDevices.getUserMedia({audio: false,
      video: {facingMode: 'user', width: {ideal: 640}, height: {ideal: 480}, frameRate: {ideal: 60, max: 60}}});
    if (generation !== this.generation) {
      stream.getTracks().forEach(track => track.stop());
      throw new Error('Webcam start cancelled.');
    }
    this.stream = stream; return stream;
  }
  close() { this.generation++; this.stream?.getTracks().forEach(track => track.stop()); this.stream = null; }
}

export class VideoAngles {
  constructor(onError = () => {}) { this.items = []; this.onError = onError; this.generation = 0; this.playing = false; this.clock = 0; this.lastDriftCheck = 0; }
  async add({stream, file, url, label = 'Camera', offset = 0}) {
    if (this.items.length >= 4) throw new Error('Use up to four video angles in this first workspace.');
    const generation = this.generation;
    const video = document.createElement('video');
    video.muted = true; video.playsInline = true; video.preload = 'auto'; video.crossOrigin = 'anonymous';
    const objectURL = file ? URL.createObjectURL(file) : null;
    const item = {id: crypto.randomUUID(), video, label, offset, objectURL, live: !!stream};
    const release = () => { video.pause(); video.srcObject = null; video.removeAttribute('src'); video.load(); if (objectURL) URL.revokeObjectURL(objectURL); };
    item.release = release;
    try {
      if (stream) video.srcObject = stream; else video.src = objectURL || url;
      if (!stream && !file && !/^https?:|^\//.test(url || '')) throw new Error('Choose an HTTP media URL or a local video file.');
      await new Promise((resolve, reject) => {
        let timer;
        const clean = () => {clearTimeout(timer);video.removeEventListener('loadeddata', ready);video.removeEventListener('error', fail);};
        const ready = () => {clean();resolve();};
        const fail = () => {clean();reject(new Error(`Cannot decode ${label}. Use a browser-compatible video with CORS enabled for remote URLs.`));};
        video.addEventListener('loadeddata', ready); video.addEventListener('error', fail);
        timer = setTimeout(() => {clean();reject(new Error(`${label} did not load within 20 seconds.`));}, 20000);
        if (video.readyState >= 2) ready();
      });
      if (generation !== this.generation) throw new Error('Video loading cancelled.');
      this.items.push(item);
      video.addEventListener('error', () => this.onError(`Playback failed for ${label}.`));
      if (stream) await video.play();
      return item;
    } catch (error) { this.items = this.items.filter(candidate => candidate !== item);release();throw error; }
  }
  get recorded() { return this.items.filter(item => !item.live); }
  get duration() { return Math.max(0, Math.min(...this.recorded.map(item => item.video.duration - item.offset), 0x7fffffff)); }
  async play() {
    if (!this.recorded.length) throw new Error('Add recorded video angles before pressing Play.');
    this.seek(this.clock);
    try { await Promise.all(this.recorded.map(item => item.video.play()));this.playing = true; }
    catch (error) {this.pause();throw new Error('Playback was blocked or an angle cannot play. Press Play again.');}
  }
  pause() {this.playing = false;this.recorded.forEach(item => item.video.pause());}
  seek(seconds) {
    this.clock = Math.max(0, Math.min(Number(seconds) || 0, this.duration));
    this.recorded.forEach(item => {item.video.currentTime = Math.max(0, Math.min(item.video.duration, this.clock + item.offset));});
  }
  tick(now) {
    const master = this.recorded[0];
    if (!master || !this.playing) return;
    this.clock = master.video.currentTime - master.offset;
    if (this.clock >= this.duration - 0.025 || master.video.ended) {this.pause();return;}
    // HTML video synchronization is approximate. Do not seek on every animation frame.
    if (now - this.lastDriftCheck < 300) return;
    this.lastDriftCheck = now;
    const stalled = this.recorded.some(item => item.video.readyState < 3);
    if (stalled) {this.recorded.forEach(item => item.video.pause());return;}
    for (const item of this.recorded) {
      const drift = item.video.currentTime - item.offset - this.clock;
      if (Math.abs(drift) > 0.15) item.video.currentTime = this.clock + item.offset;
      item.video.playbackRate = Math.abs(drift) > 0.03 ? (drift > 0 ? 0.98 : 1.02) : 1;
      if (item.video.paused) item.video.play().catch(() => {this.pause();this.onError('An angle stopped. Press Play to resume.');});
    }
  }
  remove(item) { item.release();this.items = this.items.filter(candidate => candidate !== item); }
  dispose() {this.generation++;this.pause();this.items.forEach(item => item.release());this.items = [];}
}
