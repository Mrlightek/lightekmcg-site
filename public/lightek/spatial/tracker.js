export class FaceTracker {
  constructor({onResult, onStatus, workerURL = new URL('./vision-worker.js', import.meta.url)}) {
    this.onResult = onResult; this.onStatus = onStatus; this.workerURL = workerURL;
    this.worker = null; this.ready = false; this.busy = false; this.lastTime = -1;
    this.segment = false; this.segmentReady = false; this.lastCapture = 0;
  }
  start() {
    if (this.worker) return;
    this.onStatus('Loading face tracking models…');
    const worker = this.worker = new Worker(this.workerURL);
    const fail = message => {if(this.worker !== worker)return;this.stop();this.onStatus(message);};
    this.timeout = setTimeout(() => fail('Tracking models timed out. Check the connection and try Enable tracking again.'), 30000);
    worker.onmessage = ({data}) => {
      if (this.worker !== worker) return;
      if (data.type === 'ready') {clearTimeout(this.timeout);this.ready = true;this.onStatus('Tracking ready. Face the camera, then Calibrate.');}
      if (data.type === 'segment-ready') {this.segmentReady = true;this.onStatus('Person cutout ready.');}
      if (data.type === 'result') {this.busy = false;this.onResult(data);}
      if (data.type === 'error') fail(`Tracking unavailable: ${data.message}. Webcam compositing still works.`);
    };
    worker.onerror = () => fail('Tracking could not load. Webcam compositing still works; check model downloads and retry.');
    worker.postMessage({type: 'init'});
  }
  enableSegmentation(enabled) {
    this.segment = enabled;
    if(enabled && this.ready && !this.segmentReady && !this.segmentLoading){this.segmentLoading=true;this.worker.postMessage({type:'segment'});}
  }
  async sample(video, now) {
    if (!this.ready || this.busy || (this.segmentLoading&&!this.segmentReady) || video.readyState < 2 || video.currentTime === this.lastTime || now-this.lastCapture<100) return;
    const worker = this.worker;this.busy = true;this.lastTime = video.currentTime;this.lastCapture=now;
    try {
      const bitmap = await createImageBitmap(video, {resizeWidth: 320, resizeHeight: Math.round(320 * video.videoHeight / video.videoWidth)});
      if (worker !== this.worker) {bitmap.close();return;}
      worker.postMessage({type:'frame',bitmap,time:now,segment:this.segment && this.segmentReady},[bitmap]);
    } catch (error) {this.busy=false;this.onStatus(`Cannot read webcam frame: ${error.message}`);}
  }
  stop() {clearTimeout(this.timeout);this.worker?.terminate();this.worker=null;this.ready=false;this.busy=false;this.segmentReady=false;this.segmentLoading=false;this.lastTime=-1;}
}
