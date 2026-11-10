import 'dart:convert';
import 'dart:io';

/// Checks the installed npm package metadata before enabling the built-in
/// music presentation. This is a local identity check, not a signature check.
Future<bool> isNeteaseCliPackage(String executable) async {
  if (executable.split('/').last != 'ncm-cli') return false;
  try {
    final entrypoint = await File(executable).resolveSymbolicLinks();
    var directory = File(entrypoint).parent;
    for (var level = 0; level < 5; level++) {
      final manifest = File('${directory.path}/package.json');
      if (await manifest.exists()) {
        final raw = jsonDecode(await manifest.readAsString());
        if (raw is! Map || raw['name'] != '@music163/ncm-cli') {
          return false;
        }
        final bins = raw['bin'];
        final bin = bins is Map ? bins['ncm-cli'] : bins;
        if (bin is! String ||
            bin.isEmpty ||
            bin.startsWith('/') ||
            bin.split('/').contains('..')) {
          return false;
        }
        return await File('${directory.path}/$bin').resolveSymbolicLinks() ==
            entrypoint;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
  return false;
}
