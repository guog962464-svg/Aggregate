# Test identity fixtures

`host_test_cert.pem` and `host_test_key.pem` are a disposable self-signed pair
used only by `host_tls_identity_test.dart`. The private key is intentionally
checked in as public test data; it must never be used by the app, integration
tests, or any deployed Host. Production macOS identities are generated and
stored through the macOS Keychain bridge.
