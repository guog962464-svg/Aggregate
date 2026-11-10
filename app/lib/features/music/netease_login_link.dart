/// Reads the short-lived link printed by the verified ncm-cli login process.
/// The link is kept only in memory while the QR login dialog is open.
final class NeteaseLoginLinkReader {
  static final RegExp _link = RegExp(
    r'https://163cn\.tv/[A-Za-z0-9_-]{4,80}(?=\s|\x1b)',
  );

  String _tail = '';

  String? add(String chunk) {
    _tail += chunk;
    if (_tail.length > 8192) _tail = _tail.substring(_tail.length - 8192);
    return _link.firstMatch(_tail)?.group(0);
  }

  void clear() => _tail = '';
}
