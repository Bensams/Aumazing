{{flutter_js}}
{{flutter_build_config}}

// Load CanvasKit from this build rather than Google's CDN, so the app still
// starts when it is opened offline from the service worker's cache (AUM-334).
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
