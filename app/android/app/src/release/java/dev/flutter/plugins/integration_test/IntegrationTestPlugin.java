package dev.flutter.plugins.integration_test;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * No-op release counterpart for Flutter's generated plugin registrant.
 *
 * The Flutter tool includes the dev-only integration_test plugin in
 * GeneratedPluginRegistrant.java, while the Gradle plugin correctly omits its
 * implementation from release dependencies. The app does not use the testing
 * channel in release builds, so this keeps registration compilable without
 * packaging the test plugin implementation.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {}
}
