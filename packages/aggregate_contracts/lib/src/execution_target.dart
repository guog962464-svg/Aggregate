/// Where a connection is executed, relative to the runtime that owns it.
/// A device target stays on that runtime's device. A host target names a
/// paired host with a stable ID; display names and filesystem paths are not IDs.
enum ExecutionTargetKind { device, host }

final class ExecutionTarget {
  const ExecutionTarget._(this.kind, this.hostId);

  static const device = ExecutionTarget._(ExecutionTargetKind.device, null);

  factory ExecutionTarget.host(String hostId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(hostId)) {
      throw const FormatException('invalid hostId');
    }
    return ExecutionTarget._(ExecutionTargetKind.host, hostId);
  }

  final ExecutionTargetKind kind;
  final String? hostId;

  @override
  bool operator ==(Object other) =>
      other is ExecutionTarget && other.kind == kind && other.hostId == hostId;

  @override
  int get hashCode => Object.hash(kind, hostId);

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (hostId != null) 'hostId': hostId,
  };

  /// Pre-target records belong to the runtime that stored them.
  factory ExecutionTarget.fromJson(Object? value) {
    if (value == null) return device;
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('invalid executionTarget');
    }
    final kind = switch (value['kind']) {
      'device' => ExecutionTargetKind.device,
      'host' => ExecutionTargetKind.host,
      _ => throw const FormatException('invalid executionTarget kind'),
    };
    if (kind == ExecutionTargetKind.device) {
      if (value.containsKey('hostId')) {
        throw const FormatException('device target cannot have hostId');
      }
      return device;
    }
    final hostId = value['hostId'];
    if (hostId is! String) throw const FormatException('invalid hostId');
    return ExecutionTarget.host(hostId);
  }
}
