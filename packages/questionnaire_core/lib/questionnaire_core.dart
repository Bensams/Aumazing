/// Questionnaire templates shared by the Aumazing app, which shows them to
/// parents, and the practitioner portal, where approved practitioners write
/// them (AUM-344, AUM-351, AUM-352).
///
/// Pure Dart: the same validation runs in the portal before saving and in
/// the app before showing, so a template the portal accepts is one the app
/// will use.
library;

export 'src/choice_template.dart';
export 'src/defaults.dart';
export 'src/home_items.dart';
export 'src/template_kind.dart';
