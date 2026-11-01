// Models execute locally in this worker; webcam frames are never sent to a server.
// Classic worker shell is intentional: MediaPipe's WASM loader calls importScripts().
let FaceLandmarker, ImageSegmenter, FilesetResolver;
let face, segmenter, fileset;let lastFace=null,lastFaceTime=-Infinity;
self.onmessage = async ({data}) => {
  try {
    if (data.type === 'init') {
      ({FaceLandmarker,ImageSegmenter,FilesetResolver}=await import('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/vision_bundle.mjs'));
      fileset = await FilesetResolver.forVisionTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm');
      face = await FaceLandmarker.createFromOptions(fileset, {baseOptions: {delegate: 'CPU',
        modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'},
        runningMode: 'VIDEO', numFaces: 1, minFaceDetectionConfidence: 0.6, minTrackingConfidence: 0.6});
      self.postMessage({type: 'ready'});return;
    }
    if (data.type === 'segment') {
      const create=delegate=>ImageSegmenter.createFromOptions(fileset, {baseOptions: {delegate,
        modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite'},
        runningMode: 'VIDEO', outputConfidenceMasks: true, outputCategoryMask: false});
      if(!segmenter){try{segmenter=await create('GPU');}catch{segmenter=await create('CPU');}}
      self.postMessage({type: 'segment-ready'});return;
    }
    if (data.type === 'frame') {
      try {
        const started=performance.now();
        if(data.time-lastFaceTime>=50){lastFace=face.detectForVideo(data.bitmap,data.time);lastFaceTime=data.time;}
        const result=lastFace;
        let mask = null;
        if (data.segment && segmenter) segmenter.segmentForVideo(data.bitmap, data.time, result => {
          // Models may expose one foreground channel or background/person channels. Copy while valid.
          const confidence = result.confidenceMasks?.[1] || result.confidenceMasks?.[0];
          if (confidence) mask = {width: confidence.width, height: confidence.height,
            bytes: new Float32Array(confidence.getAsFloat32Array())};
        });
        const message = {type: 'result', landmarks: result?.faceLandmarks[0] || null, mask,inferenceMs:performance.now()-started};
        self.postMessage(message, mask ? [mask.bytes.buffer] : []);
      } finally { data.bitmap.close(); }
    }
  } catch (error) { self.postMessage({type: 'error', message: error.message, phase: data.type}); }
};
