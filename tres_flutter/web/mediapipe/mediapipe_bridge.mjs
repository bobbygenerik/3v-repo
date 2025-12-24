// MediaPipe web bridge removed.
// This file is intentionally left as a placeholder to avoid build-time errors.
// All MediaPipe processing has been removed to ensure stability on Safari PWAs.

let vision;
let segmenter;
let faceLandmarker;
let initialized = false;
let optionsState = {
  backgroundBlur: false,
  beauty: false,
  faceMesh: false,
  faceDetection: false,
  blurIntensity: 70,
};
let lastCropRect = null;

async function init() {
  if (initialized) return;
  const baseUrl = new URL(document.baseURI);
  const resolveAsset = (path) => new URL(path, baseUrl).toString();
  vision = await FilesetResolver.forVisionTasks(
    resolveAsset('mediapipe/node_modules/@mediapipe/tasks-vision/wasm')
  );

  segmenter = await ImageSegmenter.createFromOptions(vision, {
    baseOptions: {
      modelAssetPath: resolveAsset('assets/assets/mediapipe/selfie_segmenter.tflite'),
    },
    runningMode: 'VIDEO',
    outputCategoryMask: true,
  });

  faceLandmarker = await FaceLandmarker.createFromOptions(vision, {
    baseOptions: {
      modelAssetPath: resolveAsset('assets/assets/mediapipe/face_landmarker.task'),
    },
    runningMode: 'VIDEO',
    outputFaceBlendshapes: false,
    outputFacialTransformationMatrixes: false,
  });

  initialized = true;
}

function updateOptions(opts) {
  optionsState = {
    ...optionsState,
    ...opts,
  };
}

function disposeProcessor() {
  // No-op for now; processors are tied to track streams.
}

function _ensureCanvasSize(canvas, width, height) {
  if (canvas.width !== width) canvas.width = width;
  if (canvas.height !== height) canvas.height = height;
}

function _buildMaskImageData(mask, width, height) {
  const data = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const value = mask[i];
    const alpha = Number.isFinite(value)
      ? Math.min(Math.max(value * 255, 0), 255)
      : value > 0
        ? 255
        : 0;
    const offset = i * 4;
    data[offset] = 0;
    data[offset + 1] = 0;
    data[offset + 2] = 0;
    data[offset + 3] = alpha;
  }
  return new ImageData(data, width, height);
}

function _computeFaceRect(landmarks, width, height) {
  let minX = 1;
  let minY = 1;
  let maxX = 0;
  let maxY = 0;

  landmarks.forEach((point) => {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  });

  if (maxX <= minX || maxY <= minY) return null;

  const centerX = (minX + maxX) * 0.5 * width;
  const centerY = (minY + maxY) * 0.5 * height;
  const faceW = (maxX - minX) * width;
  const faceH = (maxY - minY) * height;
  const targetScale = 1.9;
  let cropW = faceW * targetScale;
  let cropH = faceH * targetScale;

  const aspect = width / height;
  if (cropW / cropH > aspect) {
    cropH = cropW / aspect;
  } else {
    cropW = cropH * aspect;
  }

  let x = centerX - cropW / 2;
  let y = centerY - cropH / 2;

  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + cropW > width) x = Math.max(0, width - cropW);
  if (y + cropH > height) y = Math.max(0, height - cropH);

  return { x, y, w: cropW, h: cropH };
}

function _smoothRect(nextRect) {
  if (!nextRect) return null;
  if (!lastCropRect) {
    lastCropRect = nextRect;
    return nextRect;
  }
  const alpha = 0.2;
  const smoothed = {
    x: lastCropRect.x + (nextRect.x - lastCropRect.x) * alpha,
    y: lastCropRect.y + (nextRect.y - lastCropRect.y) * alpha,
    w: lastCropRect.w + (nextRect.w - lastCropRect.w) * alpha,
    h: lastCropRect.h + (nextRect.h - lastCropRect.h) * alpha,
  };
  lastCropRect = smoothed;
  return smoothed;
}

async function createProcessedTrack(jsTrack, opts) {
  updateOptions(opts);
  try {
    await init();
  } catch (e) {
    console.warn('MediaPipe init failed; returning original track:', e);
    return jsTrack;
  }

  if (typeof MediaStreamTrackProcessor === 'undefined' || typeof MediaStreamTrackGenerator === 'undefined') {
    console.warn('MediaPipe: MediaStreamTrackProcessor not supported; returning original track.');
    return jsTrack;
  }

  let processor;
  let generator;
  try {
    processor = new MediaStreamTrackProcessor({ track: jsTrack });
    generator = new MediaStreamTrackGenerator({ kind: 'video' });
  } catch (e) {
    console.warn('MediaPipe track processor init failed; returning original track:', e);
    return jsTrack;
  }

  const input = processor.readable;
  const output = generator.writable;

  const createCanvas = () => {
    if (typeof OffscreenCanvas !== 'undefined') {
      return new OffscreenCanvas(1, 1);
    }
    if (typeof document !== 'undefined') {
      const canvas = document.createElement('canvas');
      canvas.width = 1;
      canvas.height = 1;
      return canvas;
    }
    throw new Error('No canvas implementation available');
  };

  let canvas;
  let maskCanvas;
  let maskImageCanvas;
  let subjectCanvas;
  let blurCanvas;
  let frameCanvas;

  try {
    canvas = createCanvas();
    maskCanvas = createCanvas();
    maskImageCanvas = createCanvas();
    subjectCanvas = createCanvas();
    blurCanvas = createCanvas();
    frameCanvas = createCanvas();
  } catch (e) {
    console.warn('MediaPipe canvas init failed; returning original track:', e);
    return jsTrack;
  }

  const ctx = canvas.getContext('2d');
  const maskCtx = maskCanvas.getContext('2d');
  const maskImageCtx = maskImageCanvas.getContext('2d');
  const subjectCtx = subjectCanvas.getContext('2d');
  const blurCtx = blurCanvas.getContext('2d');
  const frameCtx = frameCanvas.getContext('2d');

  if (!ctx || !maskCtx || !maskImageCtx || !subjectCtx || !blurCtx || !frameCtx) {
    console.warn('MediaPipe canvas context unavailable; returning original track.');
    return jsTrack;
  }

  const transformer = new TransformStream({
    async transform(videoFrame, controller) {
      try {
        const width = videoFrame.displayWidth;
        const height = videoFrame.displayHeight;
        _ensureCanvasSize(canvas, width, height);
        _ensureCanvasSize(maskCanvas, width, height);
        _ensureCanvasSize(subjectCanvas, width, height);
        _ensureCanvasSize(blurCanvas, width, height);
        _ensureCanvasSize(frameCanvas, width, height);

        const timestampMs = Math.round(videoFrame.timestamp / 1000);

        let maskData;
        let faceResult;
        if (optionsState.backgroundBlur && segmenter) {
          try {
            const result = await segmenter.segmentForVideo(videoFrame, timestampMs);
            const categoryMask = result.categoryMask;
            const maskArray = categoryMask.getAsUint8Array
              ? categoryMask.getAsUint8Array()
              : categoryMask.getAsFloat32Array();
            maskData = _buildMaskImageData(maskArray, categoryMask.width, categoryMask.height);
            _ensureCanvasSize(maskImageCanvas, categoryMask.width, categoryMask.height);
            maskImageCtx.putImageData(maskData, 0, 0);
          } catch (e) {
            console.warn('MediaPipe segmenter error, passing through frame:', e);
            maskData = null;
          }
        }

        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(videoFrame, 0, 0, width, height);

        const blurIntensity = Number.isFinite(optionsState.blurIntensity)
          ? Math.min(Math.max(optionsState.blurIntensity, 0), 100)
          : 70;
        const blurPx = blurIntensity <= 0 ? 0 : Math.round(2 + (blurIntensity / 100) * 18);

        blurCtx.clearRect(0, 0, width, height);
        blurCtx.filter = blurPx > 0 ? `blur(${blurPx}px)` : 'none';
        blurCtx.drawImage(canvas, 0, 0, width, height);
        blurCtx.filter = 'none';

        if (maskData) {
          maskCtx.clearRect(0, 0, width, height);
          maskCtx.drawImage(maskImageCanvas, 0, 0, width, height);
          subjectCtx.clearRect(0, 0, width, height);
          subjectCtx.drawImage(canvas, 0, 0, width, height);
          subjectCtx.globalCompositeOperation = 'destination-in';
          subjectCtx.drawImage(maskCanvas, 0, 0, width, height);
          subjectCtx.globalCompositeOperation = 'source-over';

          ctx.clearRect(0, 0, width, height);
          ctx.drawImage(blurCanvas, 0, 0, width, height);
          ctx.drawImage(subjectCanvas, 0, 0, width, height);
        } else if (optionsState.backgroundBlur && blurPx > 0) {
          ctx.clearRect(0, 0, width, height);
          ctx.drawImage(blurCanvas, 0, 0, width, height);
        }

        if ((optionsState.beauty || optionsState.faceDetection || optionsState.faceMesh) && faceLandmarker) {
          try {
            faceResult = await faceLandmarker.detectForVideo(videoFrame, timestampMs);
          } catch (e) {
            console.warn('MediaPipe faceLandmarker error, skipping face effects:', e);
            faceResult = null;
          }
        }

        if (optionsState.beauty && faceResult?.faceLandmarks?.length > 0) {
          faceResult.faceLandmarks.forEach((landmarks) => {
            let minX = 1;
            let minY = 1;
            let maxX = 0;
            let maxY = 0;
            landmarks.forEach((point) => {
              minX = Math.min(minX, point.x);
              minY = Math.min(minY, point.y);
              maxX = Math.max(maxX, point.x);
              maxY = Math.max(maxY, point.y);
            });
            const x = Math.max(Math.floor(minX * width) - 10, 0);
            const y = Math.max(Math.floor(minY * height) - 10, 0);
            const w = Math.min(Math.ceil((maxX - minX) * width) + 20, width - x);
            const h = Math.min(Math.ceil((maxY - minY) * height) + 20, height - y);

            ctx.save();
            ctx.filter = 'blur(3px)';
            ctx.drawImage(canvas, x, y, w, h, x, y, w, h);
            ctx.restore();
          });
        }

        let outputCanvas = canvas;
        if (optionsState.faceDetection && faceResult?.faceLandmarks?.length > 0) {
          const rect = _smoothRect(_computeFaceRect(faceResult.faceLandmarks[0], width, height));
          if (rect) {
            frameCtx.clearRect(0, 0, width, height);
            frameCtx.drawImage(
              canvas,
              rect.x,
              rect.y,
              rect.w,
              rect.h,
              0,
              0,
              width,
              height
            );
            outputCanvas = frameCanvas;
          }
        } else if (!optionsState.faceDetection) {
          lastCropRect = null;
        }

        const outputFrame = new VideoFrame(outputCanvas, { timestamp: videoFrame.timestamp });
        controller.enqueue(outputFrame);
        outputFrame.close();
      } catch (e) {
        console.warn('MediaPipe processing error, passing through frame:', e);
        try {
          const width = videoFrame.displayWidth;
          const height = videoFrame.displayHeight;
          _ensureCanvasSize(canvas, width, height);
          ctx.clearRect(0, 0, width, height);
          ctx.drawImage(videoFrame, 0, 0, width, height);
          const outputFrame = new VideoFrame(canvas, { timestamp: videoFrame.timestamp });
          controller.enqueue(outputFrame);
          outputFrame.close();
        } catch (fallbackError) {
          console.error('MediaPipe fallback failed:', fallbackError);
        }
      } finally {
        videoFrame.close();
      }
    },
  });

  input.pipeThrough(transformer).pipeTo(output);

  return generator.track;
}

window.MediaPipeBridge = {
  init,
  createProcessedTrack,
  updateOptions,
  disposeProcessor,
};
