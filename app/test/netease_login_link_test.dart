import 'package:aggregate/features/music/netease_login_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a complete CLI login link across output chunks', () {
    final reader = NeteaseLoginLinkReader();
    expect(reader.add('请扫码\r\nhttps://163cn.tv/ab'), isNull);
    expect(reader.add('CD_12'), isNull);
    expect(reader.add('\r\n等待扫码中'), 'https://163cn.tv/abCD_12');
  });

  test('ignores unrelated URLs and clears the previous login output', () {
    final reader = NeteaseLoginLinkReader();
    expect(reader.add('https://example.com/abcd\n'), isNull);
    expect(reader.add('https://163cn.tv/old1\n'), 'https://163cn.tv/old1');
    reader.clear();
    expect(reader.add('https://163cn.tv/new2\x1b[0m'), 'https://163cn.tv/new2');
  });
}
