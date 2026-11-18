import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('aggregate/application_directory');

Future<Directory> androidApplicationSupportDirectory() async {
  final path = await _channel.invokeMethod<String>(
    'applicationSupportDirectory',
  );
  if (path == null || path.isEmpty) {
    throw StateError('Android did not provide the app support directory');
  }
  return Directory(path);
}
