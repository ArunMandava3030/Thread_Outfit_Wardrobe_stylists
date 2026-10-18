/* Thread's local pose bridge. Runtime, WASM and models are pinned local files.
 * Photos stay in the browser and inference runs in a dedicated worker. */
(() => {
  const base = new URL('.', document.currentScript.src);
  let worker;
  const pending = new Map();
  const stop = () => {
    if (worker) worker.terminate();
    worker = undefined;
  };
  window.threadPoseDetect = (pixels, width, height, id) => new Promise((resolve, reject) => {
    if (!window.Worker || !window.OffscreenCanvas) {
      reject(new Error('Automatic analysis is unavailable in this browser.'));
      return;
    }
    if (!worker) {
      worker = new Worker(new URL('thread_pose_worker.js', base));
      worker.onmessage = ({data}) => {
        const job = pending.get(data.id);
        if (!job) return;
        clearTimeout(job.timeout);
        pending.delete(data.id);
        if (data.error) job.reject(new Error(data.error));
        else job.resolve(JSON.stringify(data.result));
      };
      worker.onerror = () => {
        for (const job of pending.values()) {
          clearTimeout(job.timeout);
          job.reject(new Error('The local pose model could not start.'));
        }
        pending.clear();
        stop();
      };
    }
    const timeout = setTimeout(() => {
      window.threadPoseCancel(id);
    }, 45000);
    pending.set(id, {resolve, reject, timeout});
    // Copy before transferring: never detach Flutter's original image buffer.
    const rgba = new Uint8Array(pixels).buffer;
    worker.postMessage({id, rgba, width, height}, [rgba]);
  });
  window.threadPoseCancel = id => {
    const job = pending.get(id);
    if (job) {
      clearTimeout(job.timeout);
      pending.delete(id);
      job.reject(new Error('Automatic analysis stopped. Use the guided taps.'));
    }
    if (pending.size === 0) stop();
  };
})();
