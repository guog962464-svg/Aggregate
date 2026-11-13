import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android document picker returns bounded in-memory content', (
    tester,
  ) async {
    const fixture = 'Aggregate Android A8.3 document content fixture';
    await tester.runAsync(() async {
      final bytes = await const MethodChannel('aggregate/document_content')
          .invokeMethod<Uint8List>('pickSmallText');
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!).trimRight(), fixture);

      final cache = await getTemporaryDirectory();
      for (final entity in cache.listSync(recursive: true)) {
        if (entity is! File) continue;
        try {
          final content = await entity.readAsString();
          expect(content, isNot(contains(fixture)));
        } on FormatException {
          // Binary cache entries cannot contain the plain-text fixture verbatim.
        }
      }
    });
  });
}
