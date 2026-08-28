/// Shared UI package for the Aumazing app ecosystem.
///
/// Provides the complete design system: theme tokens, reusable widgets,
/// and common utilities used by both main_app and game_lab.
library shared_ui;

// Theme / design tokens
export 'src/theme/theme.dart';

// Localization (curated EN / TL / CEB strings)
export 'src/i18n/app_strings.dart';

// Reusable widgets
export 'src/widgets/widgets.dart';

// Utilities
export 'src/utils/device_form_factor.dart';
export 'src/utils/text_fit.dart';
export 'src/utils/parent_screen_orientation.dart';
