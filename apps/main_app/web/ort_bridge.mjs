// Bridge between Dart (dart:js_interop) and onnxruntime-web.
//
// The Dart `onnxruntime` package is native-only (dart:ffi), so on the web the
// on-device AI service (on_device_ai_assessment_service_web.dart) drives the
// WASM build of ONNX Runtime through the small `window.aumazingAI` API defined
// here. Inference stays fully in the browser — no server, same models as the
// Android build.
import * as ort from './ort/ort.wasm.min.mjs';

// Single-threaded avoids needing cross-origin isolation (SharedArrayBuffer),
// and point the runtime at the WASM binaries we bundle next to this module.
ort.env.wasm.numThreads = 1;
ort.env.wasm.wasmPaths = new URL('./ort/', import.meta.url).href;

const sessions = Object.create(null);

window.aumazingAI = {
  ready: true,

  // Create (once) an inference session for `key` from raw .onnx bytes.
  // Returns the model's first input name.
  async createSession(key, bytes) {
    if (!sessions[key]) {
      sessions[key] = await ort.InferenceSession.create(bytes, {
        executionProviders: ['wasm']
      });
    }
    return sessions[key].inputNames[0];
  },

  // Run inference for `key` on a Float32Array of `cols` features shaped [1, cols].
  // Returns the probabilities row (a plain number[]), or null if not found.
  async run(key, floatArray, cols) {
    const session = sessions[key];
    if (!session) return null;
    const tensor = new ort.Tensor('float32', floatArray, [1, cols]);
    const feeds = {};
    feeds[session.inputNames[0]] = tensor;
    const output = await session.run(feeds);
    // The probabilities tensor is the float output with >= 2 values
    // (the label output is int64 with a single value).
    for (const name of session.outputNames) {
      const data = output[name] && output[name].data;
      if (data && data.length >= 2 && !(data instanceof BigInt64Array)) {
        return Array.from(data, Number);
      }
    }
    return null;
  }
};

window.dispatchEvent(new Event('aumazing-ai-ready'));
