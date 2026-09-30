import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/services/external_app_checker.dart';

void main() {
  group('ExternalAppChecker.extractVersion', () {
    test('extracts standard semantic versions', () {
      expect(ExternalAppChecker.extractVersion('1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('v1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('Version 1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('version 1.2.3'), '1.2.3');
    });

    test('extracts versions with pre-release tags', () {
      expect(ExternalAppChecker.extractVersion('1.2.3-beta.1'), '1.2.3-beta.1');
      expect(ExternalAppChecker.extractVersion('v2.0.0-rc1'), '2.0.0-rc1');
      expect(ExternalAppChecker.extractVersion('1.0.0-alpha'), '1.0.0-alpha');
    });

    test('extracts versions from messy output', () {
      expect(ExternalAppChecker.extractVersion('git version 2.34.1'), '2.34.1');
      expect(ExternalAppChecker.extractVersion('Docker version 24.0.5, build ced0996'), '24.0.5');
      expect(ExternalAppChecker.extractVersion('Python 3.10.12'), '3.10.12');
      expect(ExternalAppChecker.extractVersion('autononext 0.3.5'), '0.3.5');
    });

    test('extracts short versions', () {
      expect(ExternalAppChecker.extractVersion('1.2'), '1.2');
      expect(ExternalAppChecker.extractVersion('v1.2'), '1.2');
    });

    test('returns null for unparseable output', () {
      expect(ExternalAppChecker.extractVersion('command not found'), isNull);
      expect(ExternalAppChecker.extractVersion('No package found matching'), isNull);
    });
  });
}
