import 'dart:convert';
import 'dart:io';

import 'package:aggregate_contracts/aggregate_contracts.dart';

/// Atomic JSON files in the app support directory. Connection secrets live in
/// AndroidCredentialStore, never in these files.
final class AndroidRuntimeStore {
  AndroidRuntimeStore(this.directory);

  final Directory directory;
  Future<void> _writes = Future<void>.value();

  Future<void> flush() => _writes;

  File _file(String name) => File('${directory.path}/$name.json');

  Future<String?> backupDamaged(String name) async {
    final original = _file(name);
    if (!await original.exists()) return null;
    final backup =
        '${original.path}.damaged-${DateTime.now().microsecondsSinceEpoch}';
    await original.copy(backup);
    return backup;
  }

  Future<Object?> read(String name) async {
    final file = _file(name);
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> write(String name, Object value) {
    final next = _writes.then((_) async {
      await directory.create(recursive: true);
      final target = _file(name);
      final temp = File('${target.path}.tmp');
      try {
        await temp.writeAsString(jsonEncode(value), flush: true);
        await temp.rename(target.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<List<({String id, ConnectionSpec spec})>> loadConnections() async {
    final raw = await read('connections');
    if (raw == null) return [];
    final json = jsonObject(raw, 'connections');
    if (json['schemaVersion'] != 1 || json['connections'] is! List) {
      throw const FormatException('连接配置格式无效');
    }
    return [
      for (final item in json['connections'] as List)
        (
          id: jsonString(jsonObject(item, 'connection'), 'id'),
          spec: ConnectionSpec.fromJson(jsonObject(item, 'connection')['spec']),
        ),
    ];
  }

  Future<void> saveConnections(
    Iterable<({String id, ConnectionSpec spec})> entries,
  ) => write('connections', {
    'schemaVersion': 1,
    'connections': [
      for (final entry in entries)
        {'id': entry.id, 'spec': entry.spec.toJson()},
    ],
  });
}
