import 'package:aggregate_contracts/aggregate_contracts.dart';

final class ConnectionLifecycle {
  ConnectionLifecycle(this.status);
  ConnectionStatus status;

  void transition(ConnectionStatus next) {
    if (status == next) return;
    final allowed = switch (status) {
      ConnectionStatus.ready => {
        ConnectionStatus.connecting,
        ConnectionStatus.unavailable,
      },
      ConnectionStatus.connecting => {
        ConnectionStatus.ready,
        ConnectionStatus.unavailable,
      },
      ConnectionStatus.unavailable => {ConnectionStatus.connecting},
    };
    if (!allowed.contains(next)) {
      throw StateError('invalid connection transition: $status -> $next');
    }
    status = next;
  }
}

final class RunLifecycle {
  RunLifecycle(this.state);
  RunState state;

  static const terminal = {
    RunState.succeeded,
    RunState.failed,
    RunState.cancelled,
    RunState.timedOut,
    RunState.outcomeUnknown,
  };

  void transition(RunState next) {
    final allowed = switch (state) {
      RunState.created => {RunState.validating, RunState.cancelled},
      RunState.validating => {
        RunState.awaitingPermission,
        RunState.running,
        RunState.failed,
        RunState.cancelled,
      },
      RunState.awaitingPermission => {
        RunState.running,
        RunState.failed,
        RunState.cancelled,
      },
      RunState.running => terminal,
      _ => <RunState>{},
    };
    if (!allowed.contains(next)) {
      throw StateError('invalid run transition: $state -> $next');
    }
    state = next;
  }
}

final class CapabilityCatalog {
  CapabilityCatalog({
    Iterable<Connection> connections = const [],
    Iterable<Capability> capabilities = const [],
  }) {
    replace(connections: connections, capabilities: capabilities);
  }

  final _connections = <String, Connection>{};
  final _capabilities = <String, Capability>{};
  final _favorites = <String>{};
  final _recent = <String>[];

  void replace({
    required Iterable<Connection> connections,
    required Iterable<Capability> capabilities,
  }) {
    _connections
      ..clear()
      ..addEntries(connections.map((item) => MapEntry(item.id.value, item)));
    _capabilities
      ..clear()
      ..addEntries(capabilities.map((item) => MapEntry(item.id.key, item)));
    _favorites.removeWhere((key) => !_capabilities.containsKey(key));
    _recent.removeWhere((key) => !_capabilities.containsKey(key));
  }

  List<Capability> search(SearchQuery query) {
    final term = query.text.trim().toLowerCase();
    final matching = _capabilities.values.where((capability) {
      if (query.kind != null && capability.id.kind != query.kind) return false;
      if (term.isEmpty) return true;
      final source = _connections[capability.id.connection.value]?.label ?? '';
      return [
        capability.title,
        capability.description,
        capability.id.name,
        source,
      ].any((text) => text.toLowerCase().contains(term));
    }).toList();
    matching.sort((a, b) {
      final favoriteCompare =
          (_favorites.contains(b.id.key) ? 1 : 0) -
          (_favorites.contains(a.id.key) ? 1 : 0);
      if (favoriteCompare != 0) return favoriteCompare;
      return a.title.compareTo(b.title);
    });
    return matching;
  }

  Connection? sourceOf(CapabilityId id) => _connections[id.connection.value];
  Capability? byId(CapabilityId id) => _capabilities[id.key];

  void setFavorite(CapabilityId id, bool favorite) {
    if (!_capabilities.containsKey(id.key)) {
      throw ArgumentError('unknown capability');
    }
    if (favorite) {
      _favorites.add(id.key);
    } else {
      _favorites.remove(id.key);
    }
  }

  List<Capability> get favorites => [
    for (final key in _favorites) ?_capabilities[key],
  ];

  void markUsed(CapabilityId id) {
    if (!_capabilities.containsKey(id.key)) {
      throw ArgumentError('unknown capability');
    }
    _recent.remove(id.key);
    _recent.insert(0, id.key);
    if (_recent.length > 20) _recent.removeLast();
  }

  List<Capability> get recent => [
    for (final key in _recent) ?_capabilities[key],
  ];
}

final class ResultNormalizer {
  static List<ResultBlock> fromMcp(JsonMap result) {
    final blocks = <ResultBlock>[];
    final structured = result['structuredContent'];
    if (structured != null) {
      blocks.add(ResultBlock(ResultKind.json, structured));
    }
    final content = result['content'];
    if (content is List) {
      for (final raw in content) {
        if (raw is! Map) continue;
        final item = jsonObject(raw, 'content');
        final type = item['type'];
        if (type == 'text' && item['text'] is String) {
          blocks.add(ResultBlock(ResultKind.text, item['text']));
        } else if (type == 'image') {
          blocks.add(ResultBlock(ResultKind.image, item));
        } else if (type == 'resource_link') {
          blocks.add(ResultBlock(ResultKind.file, item));
        }
      }
    }
    return blocks;
  }
}
