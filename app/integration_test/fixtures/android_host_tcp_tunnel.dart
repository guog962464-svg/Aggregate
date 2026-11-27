import 'dart:io';

final class AndroidHostTcpTunnelProxy {
  AndroidHostTcpTunnelProxy._(this._server, this._targetPort);

  final ServerSocket _server;
  final int _targetPort;
  final List<_AndroidHostTcpTunnel> _tunnels = [];

  int get port => _server.port;

  static Future<AndroidHostTcpTunnelProxy> start({
    required int targetPort,
    InternetAddress? bindAddress,
  }) async {
    final server = await ServerSocket.bind(
      bindAddress ?? InternetAddress.loopbackIPv4,
      0,
    );
    final proxy = AndroidHostTcpTunnelProxy._(server, targetPort);
    server.listen(proxy._accept);
    return proxy;
  }

  Future<void> _accept(Socket downstream) async {
    try {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _targetPort,
      );
      final tunnel = _AndroidHostTcpTunnel(downstream, upstream);
      _tunnels.add(tunnel);
      tunnel.forward();
    } on Object {
      downstream.destroy();
    }
  }

  Future<void> dropActiveTunnels() async {
    if (_tunnels.isEmpty) {
      throw StateError('No TCP tunnel was established');
    }
    for (final tunnel in _tunnels) {
      tunnel.destroy();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> close() async {
    await _server.close();
    for (final tunnel in _tunnels) {
      tunnel.destroy();
    }
    _tunnels.clear();
  }
}

final class _AndroidHostTcpTunnel {
  _AndroidHostTcpTunnel(this._downstream, this._upstream);

  final Socket _downstream;
  final Socket _upstream;

  void forward() {
    _pipe(_downstream, _upstream);
    _pipe(_upstream, _downstream);
  }

  void _pipe(Socket source, Socket target) {
    source.listen(
      (data) {
        try {
          target.add(data);
        } on Object {
          destroy();
        }
      },
      onError: (Object _) => destroy(),
      onDone: target.destroy,
      cancelOnError: true,
    );
  }

  void destroy() {
    _downstream.destroy();
    _upstream.destroy();
  }
}
