// Prints the bundled templates as JSON, for tools outside Dart such as the
// expert content-validity rating kit (docs/validation).
//
//   dart run tool/export_templates.dart > templates.json
import 'dart:convert';

import 'package:questionnaire_core/questionnaire_core.dart';

void main() {
  Map<String, Object?> choice(ChoiceTemplate t) => {
    'template_key': t.key,
    'version': t.version,
    'title': t.title,
    'intro': t.intro,
    'items': t.itemsJson(),
  };
  print(const JsonEncoder.withIndent('  ').convert({
    'home': {...kDefaultHomeTemplate, 'domains': kHomeDomains},
    'intake': choice(kDefaultIntakeTemplate),
    'observation': choice(kDefaultObservationTemplate),
  }));
}
