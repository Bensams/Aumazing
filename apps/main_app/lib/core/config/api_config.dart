/// Configuration for external API endpoints.
class ApiConfig {
  ApiConfig._();

  /// AI Assessment API base URL.
  ///
  /// Development: Use local FastAPI server or Android emulator localhost.
  /// Production: Use Azure App Service URL.
  static const String aiAssessmentBaseUrl = String.fromEnvironment(
    'AI_API_URL',
    defaultValue: 'https://aumazing-ai-assessment.azurewebsites.net',
  );

  /// Timeout for AI API requests in seconds.
  static const int aiApiTimeoutSeconds = 15;
}
