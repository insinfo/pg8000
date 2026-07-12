import 'package:dargres/src/connection_settings.dart';
import 'package:test/test.dart';

void main() {
  group('ReconnectPolicy', () {
    test('uses bounded exponential delays', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 350),
        jitterFactor: 0,
      );

      expect(policy.delayForAttempt(1), const Duration(milliseconds: 100));
      expect(policy.delayForAttempt(2), const Duration(milliseconds: 200));
      expect(policy.delayForAttempt(3), const Duration(milliseconds: 350));
      expect(policy.delayForAttempt(20), const Duration(milliseconds: 350));
    });

    test('applies deterministic jitter without exceeding maximum', () {
      const policy = ReconnectPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 500),
        jitterFactor: 0.2,
      );

      expect(policy.delayForAttempt(1, jitterUnit: 0),
          const Duration(milliseconds: 80));
      expect(policy.delayForAttempt(1, jitterUnit: 0.5),
          const Duration(milliseconds: 100));
      expect(policy.delayForAttempt(1, jitterUnit: 1),
          const Duration(milliseconds: 120));
      expect(policy.delayForAttempt(10, jitterUnit: 1),
          const Duration(milliseconds: 500));
    });

    test('rejects invalid attempt and jitter inputs', () {
      const policy = ReconnectPolicy();
      expect(() => policy.delayForAttempt(0), throwsRangeError);
      expect(() => policy.delayForAttempt(1, jitterUnit: -0.1),
          throwsRangeError);
      expect(() => policy.delayForAttempt(1, jitterUnit: 1.1),
          throwsRangeError);
    });
  });
}
