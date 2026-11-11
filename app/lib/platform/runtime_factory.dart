import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';

import 'android/android_runtime_port.dart';
import 'macos/local_runtime_port.dart';

Future<RuntimePort> createRuntimePort() {
  if (Platform.isMacOS) return LocalRuntimePort.createLive();
  if (Platform.isAndroid) return Future.value(AndroidRuntimePort());
  throw UnsupportedError('当前平台尚未支持');
}
