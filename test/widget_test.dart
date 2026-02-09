import 'package:app_finanzas/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app settings defaults are valid', () {
    final settings = AppSettings.defaults();

    expect(settings.currencyCode, 'CLP');
    expect(settings.localeCode, 'es_CL');
    expect(settings.activeAccounts, isNotEmpty);
    expect(settings.activeCategories, isNotEmpty);
    expect(settings.budgetCycleDay, inInclusiveRange(1, 28));
  });
}
