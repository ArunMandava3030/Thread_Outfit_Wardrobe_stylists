let detectorPromise;
async function detector() {
  if (!detectorPromise) {
    detectorPromise = (async () => {
      const {FilesetResolver, PoseLandmarker} = await import('./vision_bundle.mjs');
      const wasm = await FilesetResolver.forVisionTasks(new URL('wasm', self.location.href).href);
      return PoseLandmarker.createFromOptions(wasm, {
        baseOptions: {
          modelAssetPath: new URL('pose_landmarker_lite.task', self.location.href).href,
          delegate: 'CPU',
        },
        runningMode: 'IMAGE',
        numPoses: 2,
        minPoseDetectionConfidence: 0.55,
        minPosePresenceConfidence: 0.55,
        outputSegmentationMasks: false,
        canvas: new OffscreenCanvas(1, 1),
      });
    })().catch(error => {
      detectorPromise = undefined;
      throw error;
    });
  }
  return detectorPromise;
}

// MediaPipe indexes mapped into MoveNet/COCO order for shared Dart processing.
const indexes = [0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];
let queue = Promise.resolve();
self.onmessage = ({data}) => {
  queue = queue.then(async () => {
    try {
      const model = await detector();
      const canvas = new OffscreenCanvas(data.width, data.height);
      const context = canvas.getContext('2d');
      context.putImageData(new ImageData(new Uint8ClampedArray(data.rgba), data.width, data.height), 0, 0);
      const result = model.detect(canvas);
      const landmarks = result.landmarks[0] || [];
      const points = landmarks.length ? indexes.map(index => ({
        x: landmarks[index].x,
        y: landmarks[index].y,
        z: landmarks[index].z,
        score: Math.min(landmarks[index].visibility ?? 0, landmarks[index].presence ?? 1),
      })) : [];
      self.postMessage({id: data.id, result: {people: result.landmarks.length, points}});
      result.close();
      canvas.width = 1;
      canvas.height = 1;
    } catch (error) {
      self.postMessage({id: data.id, error: String(error.message || error)});
    }
  });
};
