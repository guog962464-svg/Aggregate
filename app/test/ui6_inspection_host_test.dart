import 'package:aggregate/preview/ui6_inspection_host.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/platform/macos/host/host_pairing_authority.dart';

void main() {
  test(
    'Host fixture matches the v9 permission board with distinct devices',
    () async {
      final host = Ui6InspectionHost();
      addTearDown(host.dispose);

      await host.start();

      final pending = (await host.pendingRequests()).single;
      final paired = (await host.pairedDevices()).single;
      expect(pending.displayName, 'Pixel 9');
      expect(pending.deviceId, host.inspectionPendingDeviceId);
      expect(paired.displayName, 'LGE AN10');
      expect(paired.deviceId, host.inspectionPairedDeviceId);
      expect(pending.deviceId, isNot(paired.deviceId));
      expect(paired.scopes, {
        HostGrantScope.readConnections,
        HostGrantScope.connectionSetup,
        HostGrantScope.connectionManagement,
      });
      expect(paired.connectionPermissions, {
        'ui6-review-git': {PermissionLevel.read, PermissionLevel.localControl},
        'ui6-review-mcp': {PermissionLevel.read},
        'ui6-review-music': {
          PermissionLevel.read,
          PermissionLevel.externalWrite,
        },
      });

      final approved = await host.approvePending(
        pending.deviceId,
        scopes: const {HostGrantScope.readConnections},
      );
      expect(approved.deviceId, pending.deviceId);
      expect(approved.publicKeySpki, isNot(paired.publicKeySpki));
    },
  );
}
