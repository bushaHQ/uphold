import 'package:flutter_test/flutter_test.dart';
import 'package:uphold/uphold.dart';

void main() {
  group('UpholdPaymentWidgetController', () {
    test('isAttached is false initially', () {
      final controller = UpholdPaymentWidgetController();
      expect(controller.isAttached, isFalse);
      controller.dispose();
    });

    test('dispose sets isAttached to false', () {
      final controller = UpholdPaymentWidgetController();
      controller.dispose();
      expect(controller.isAttached, isFalse);
    });

    test('reload does not throw when not attached', () async {
      final controller = UpholdPaymentWidgetController();
      // Should be a no-op, not an error.
      await controller.reload();
      controller.dispose();
    });
  });
}
