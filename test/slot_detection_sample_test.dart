import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tool_forecast/services/slot_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detect sample bcr screenshot via template', () async {
    const paths = [
      r'C:\Users\daodu\.cursor\projects\d-KJC-app\assets\c__Users_daodu_AppData_Roaming_Cursor_User_workspaceStorage_420cf331a0a6a497698119848f9fcb06_images_image-3ddc0bc7-f372-4686-97d6-49146a47e42a.png',
      r'C:\Users\daodu\.cursor\projects\d-KJC-app\assets\c__Users_daodu_AppData_Roaming_Cursor_User_workspaceStorage_420cf331a0a6a497698119848f9fcb06_images_Untitled-335f58ac-8843-4fbe-8206-6dbfc9a7e139.png',
    ];
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      final r = await SlotDetectionService.detectFromScreenshot(path);
      // ignore: avoid_print
      print('[$path] success=${r.success} cards=${r.cardsDetected} debug=${r.debug}');
      expect(r.success, isTrue, reason: r.debug);
      expect(r.cardsDetected, greaterThanOrEqualTo(4));
    }
  });
}
