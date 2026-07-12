import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

void main() {
  test('command timeout settings are bounded and preserved by clone', () {
    final settings = ConnectionSettings(
      user: 'dart',
      commandTimeout: const Duration(seconds: 12),
      cancelGracePeriod: const Duration(seconds: 3),
    );
    final clone = settings.clone();

    expect(clone.commandTimeout, const Duration(seconds: 12));
    expect(clone.cancelGracePeriod, const Duration(seconds: 3));
    expect(
      () => ConnectionSettings(user: 'dart', commandTimeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => ConnectionSettings(
        user: 'dart',
        cancelGracePeriod: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('command timeout can be disabled explicitly', () {
    final settings = ConnectionSettings(user: 'dart', commandTimeout: null);
    expect(settings.commandTimeout, isNull);
    expect(settings.clone().commandTimeout, isNull);
  });
}
