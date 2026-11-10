import 'dart:convert';
import 'dart:io';

import 'package:aggregate/platform/macos/netease_cli_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes the matching npm package entrypoint', () async {
    final root = await Directory.systemTemp.createTemp('aggregate-ncm-id-');
    addTearDown(() => root.delete(recursive: true));
    final package = Directory('${root.path}/node_modules/@music163/ncm-cli');
    final dist = Directory('${package.path}/dist');
    await dist.create(recursive: true);
    final entry = File('${dist.path}/index.js');
    await entry.writeAsString('#!/usr/bin/env node\n');
    final link = Link('${root.path}/ncm-cli');
    await link.create(entry.path);
    final manifest = File('${package.path}/package.json');
    await manifest.writeAsString(
      jsonEncode({
        'name': '@music163/ncm-cli',
        'version': '0.1.7',
        'bin': {'ncm-cli': 'dist/index.js'},
      }),
    );

    expect(await isNeteaseCliPackage(link.path), isTrue);

    await manifest.writeAsString(
      jsonEncode({
        'name': 'unrelated-package',
        'bin': {'ncm-cli': 'dist/index.js'},
      }),
    );
    expect(await isNeteaseCliPackage(link.path), isFalse);

    await manifest.writeAsString(
      jsonEncode({
        'name': '@music163/ncm-cli',
        'bin': {'ncm-cli': 'dist/another.js'},
      }),
    );
    expect(await isNeteaseCliPackage(link.path), isFalse);
  });
}
