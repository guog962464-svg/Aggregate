import 'ui6_inspection_main.dart' as inspection;

/// macOS design review entrypoint.
///
/// It intentionally delegates to the same AggregateApp and in-memory runtime
/// as the existing inspection preview so the visual review cannot drift into
/// a separately implemented HTML or mock-widget design.
Future<void> main() => inspection.main();
