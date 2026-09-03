/// On-device AI assessment service.
///
/// The real implementation ([on_device_ai_assessment_service_native.dart]) runs
/// the XGBoost classifiers through ONNX Runtime, which depends on `dart:ffi` and
/// therefore cannot compile for the web. When targeting the browser, the
/// conditional export below swaps in a stub
/// ([on_device_ai_assessment_service_web.dart]) that reports the model as
/// unavailable, so the caller falls back to the cloud API / rubric scoring.
///
/// Both files expose the same `OnDeviceAiAssessmentService` API, so no call site
/// needs to know which platform it is running on.
export 'on_device_ai_assessment_service_native.dart'
    if (dart.library.html) 'on_device_ai_assessment_service_web.dart';
