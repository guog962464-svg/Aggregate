import 'package:flutter/material.dart';

import 'app/aggregate_app.dart';
import 'platform/macos/local_runtime_port.dart';

void main() => runApp(AggregateApp(runtime: LocalRuntimePort.preview()));
