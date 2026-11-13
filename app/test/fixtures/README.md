# Test identity fixtures

`host_test_cert.pem` and `host_test_key.pem` are a disposable self-signed pair
used by automated TLS and P-256 signature tests. The private key is
intentionally checked in as public test data; it must never be used by the app
or any deployed Host. Production macOS identities are generated and stored
through the macOS Keychain bridge. The signature compatibility vector is a
fixed OpenSSL fixture; it does not claim to be a signature captured from a
physical Android Keystore.
