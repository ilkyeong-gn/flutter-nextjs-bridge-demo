import 'package:flutter_test/flutter_test.dart';
import 'package:app/config.dart';

void main() {
  group('getBaseUrl', () {
    test('returns Android emulator loopback for Android', () {
      expect(getBaseUrl(isAndroid: true), 'http://10.0.2.2:3000');
    });

    test('returns localhost for non-Android platforms', () {
      expect(getBaseUrl(isAndroid: false), 'http://localhost:3000');
    });
  });
}
