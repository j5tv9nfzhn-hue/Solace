import 'package:flutter_test/flutter_test.dart';
import 'package:solace/config/constants.dart';

void main() {
  group('BT Agent regressions', () {
    test('force mode confirmation covers every BT child permission', () {
      expect(PrefKeys.btAllPermissionKeys, hasLength(23));
      expect(PrefKeys.btAllPermissionKeys.toSet(),
          hasLength(PrefKeys.btAllPermissionKeys.length));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionMoments));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionLetters));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionDiary));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionLuckyWheel));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionGlobalMemory));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionProfileAvatar));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionLightTheme));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionDarkTheme));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionSystemTheme));
    });
  });
}