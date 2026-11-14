import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass_design_tokens.dart';
import 'glass_motion.dart';

/// The shared, rounded dot-matrix vocabulary used by macOS glass actions.
///
/// Material icon names used by the current app are mapped explicitly so a
/// later page migration cannot silently fall back to a different icon family.
enum GlassGlyph {
  play,
  pause,
  next,
  previous,
  plus,
  stop,
  copy,
  paste,
  save,
  terminal,
  check,
  close,
  search,
  refresh,
  music,
  grid,
  network,
  activity,
  settings,
  link,
  trash,
  export,
  shield,
  list,
  folder,
  star,
  arrow,
  arrowBack,
  arrowUp,
  arrowDown,
  filter,
  brightness,
  build,
  chat,
  device,
  phone,
  lock,
  document,
  account,
  desktop,
  externalLink,
  hourglass,
  inbox,
  history,
  info,
  error,
  key,
  qr,
  code,
  tune,
  visibility,
  flash,
  chevron,
  playlist,
  data,
  expand,
  collapse,
  appearance,
}

/// Canonical design-space points shared by static glyphs and later poses.
abstract final class GlassGlyphFactory {
  static List<Offset> pointsFor(GlassGlyph glyph) =>
      _GlyphGeometryCache.get(glyph).points;
}

abstract final class GlassGlyphCatalog {
  /// Maps the Material icon names currently used in app/lib to this glyph
  /// family. Unknown names fail loudly during a page migration.
  static GlassGlyph fromMaterialIconName(String name) => switch (name) {
    'account_circle_outlined' => GlassGlyph.account,
    'add' => GlassGlyph.plus,
    'arrow_back' => GlassGlyph.arrowBack,
    'arrow_downward' => GlassGlyph.arrowDown,
    'arrow_forward_rounded' => GlassGlyph.arrow,
    'arrow_upward' => GlassGlyph.arrowUp,
    'brightness_auto_outlined' => GlassGlyph.appearance,
    'build_outlined' => GlassGlyph.build,
    'chat_bubble_outline' => GlassGlyph.chat,
    'check_circle_outline' || 'check' => GlassGlyph.check,
    'chevron_right' => GlassGlyph.chevron,
    'close' => GlassGlyph.close,
    'content_paste' || 'content_paste_outlined' => GlassGlyph.paste,
    'copy' || 'copy_outlined' => GlassGlyph.copy,
    'dark_mode' || 'light_mode' => GlassGlyph.appearance,
    'data_object' => GlassGlyph.data,
    'delete_outline' => GlassGlyph.trash,
    'description_outlined' => GlassGlyph.document,
    'desktop_mac' ||
    'desktop_mac_outlined' ||
    'desktop_windows_outlined' => GlassGlyph.desktop,
    'devices_outlined' => GlassGlyph.device,
    'edit_outlined' => GlassGlyph.build,
    'error_outline' => GlassGlyph.error,
    'file_open_outlined' || 'folder_open_outlined' => GlassGlyph.folder,
    'flash_off' || 'flash_on' => GlassGlyph.flash,
    'grid_view_outlined' => GlassGlyph.grid,
    'history' || 'history_outlined' => GlassGlyph.history,
    'hourglass_empty' || 'hourglass_top_outlined' => GlassGlyph.hourglass,
    'hub' || 'hub_outlined' || 'lan_outlined' => GlassGlyph.network,
    'inbox_outlined' => GlassGlyph.inbox,
    'info_outline' => GlassGlyph.info,
    'key_off_outlined' || 'vpn_key_outlined' => GlassGlyph.key,
    'link' => GlassGlyph.link,
    'lock_outline' => GlassGlyph.lock,
    'manage_search' ||
    'manage_search_outlined' ||
    'search' ||
    'search_outlined' => GlassGlyph.search,
    'music_note_outlined' || 'music_note_rounded' => GlassGlyph.music,
    'open_in_full' => GlassGlyph.expand,
    'open_in_new' => GlassGlyph.externalLink,
    'pause' || 'pause_rounded' => GlassGlyph.pause,
    'phone_android' || 'phone_android_outlined' => GlassGlyph.phone,
    'play_arrow' ||
    'play_arrow_rounded' ||
    'play_circle_outline' => GlassGlyph.play,
    'playlist_add' => GlassGlyph.playlist,
    'qr_code_2' || 'qr_code_scanner' => GlassGlyph.qr,
    'refresh' || 'refresh_rounded' => GlassGlyph.refresh,
    'save_alt' => GlassGlyph.save,
    'skip_next' || 'skip_next_rounded' => GlassGlyph.next,
    'skip_previous' || 'skip_previous_rounded' => GlassGlyph.previous,
    'star_border_rounded' || 'star_rounded' => GlassGlyph.star,
    'stop' || 'stop_circle_outlined' => GlassGlyph.stop,
    'terminal' || 'terminal_outlined' => GlassGlyph.terminal,
    'tune' || 'tune_outlined' => GlassGlyph.tune,
    'unfold_less' => GlassGlyph.collapse,
    'unfold_more' => GlassGlyph.expand,
    'visibility_outlined' => GlassGlyph.visibility,
    _ => throw ArgumentError.value(name, 'name', 'Unknown Material glyph name'),
  };

  /// Resolves a Material icon by its stable code point. This lets existing
  /// IconButton call sites migrate without inspecting debug strings or
  /// changing their operation callbacks.
  static GlassGlyph fromMaterialIcon(IconData icon) {
    if (icon.fontFamily != 'MaterialIcons') {
      throw ArgumentError.value(
        icon.fontFamily,
        'icon.fontFamily',
        'Only Material icons have a glass glyph mapping',
      );
    }
    final glyph = _materialCodePointGlyphs[icon.codePoint];
    if (glyph == null) {
      throw ArgumentError.value(
        icon.codePoint,
        'icon.codePoint',
        'Unknown Material glyph code point',
      );
    }
    return glyph;
  }
}

final _materialCodePointGlyphs = <int, GlassGlyph>{
  Icons.account_circle_outlined.codePoint: GlassGlyph.account,
  Icons.add.codePoint: GlassGlyph.plus,
  Icons.arrow_back.codePoint: GlassGlyph.arrowBack,
  Icons.arrow_downward.codePoint: GlassGlyph.arrowDown,
  Icons.arrow_forward_rounded.codePoint: GlassGlyph.arrow,
  Icons.arrow_upward.codePoint: GlassGlyph.arrowUp,
  Icons.brightness_auto_outlined.codePoint: GlassGlyph.appearance,
  Icons.build_outlined.codePoint: GlassGlyph.build,
  Icons.chat_bubble_outline.codePoint: GlassGlyph.chat,
  Icons.check_circle_outline.codePoint: GlassGlyph.check,
  Icons.check.codePoint: GlassGlyph.check,
  Icons.chevron_right.codePoint: GlassGlyph.chevron,
  Icons.close.codePoint: GlassGlyph.close,
  Icons.content_paste.codePoint: GlassGlyph.paste,
  Icons.content_paste_outlined.codePoint: GlassGlyph.paste,
  Icons.copy.codePoint: GlassGlyph.copy,
  Icons.copy_outlined.codePoint: GlassGlyph.copy,
  Icons.dark_mode.codePoint: GlassGlyph.appearance,
  Icons.data_object.codePoint: GlassGlyph.data,
  Icons.delete_outline.codePoint: GlassGlyph.trash,
  Icons.description_outlined.codePoint: GlassGlyph.document,
  Icons.desktop_mac.codePoint: GlassGlyph.desktop,
  Icons.desktop_mac_outlined.codePoint: GlassGlyph.desktop,
  Icons.desktop_windows_outlined.codePoint: GlassGlyph.desktop,
  Icons.devices_outlined.codePoint: GlassGlyph.device,
  Icons.edit_outlined.codePoint: GlassGlyph.build,
  Icons.error_outline.codePoint: GlassGlyph.error,
  Icons.file_open_outlined.codePoint: GlassGlyph.folder,
  Icons.flash_off.codePoint: GlassGlyph.flash,
  Icons.flash_on.codePoint: GlassGlyph.flash,
  Icons.folder_open_outlined.codePoint: GlassGlyph.folder,
  Icons.grid_view_outlined.codePoint: GlassGlyph.grid,
  Icons.history.codePoint: GlassGlyph.history,
  Icons.history_outlined.codePoint: GlassGlyph.history,
  Icons.hourglass_empty.codePoint: GlassGlyph.hourglass,
  Icons.hourglass_top_outlined.codePoint: GlassGlyph.hourglass,
  Icons.hub.codePoint: GlassGlyph.network,
  Icons.hub_outlined.codePoint: GlassGlyph.network,
  Icons.inbox_outlined.codePoint: GlassGlyph.inbox,
  Icons.info_outline.codePoint: GlassGlyph.info,
  Icons.key_off_outlined.codePoint: GlassGlyph.key,
  Icons.lan_outlined.codePoint: GlassGlyph.network,
  Icons.light_mode.codePoint: GlassGlyph.appearance,
  Icons.link.codePoint: GlassGlyph.link,
  Icons.lock_outline.codePoint: GlassGlyph.lock,
  Icons.manage_search.codePoint: GlassGlyph.search,
  Icons.manage_search_outlined.codePoint: GlassGlyph.search,
  Icons.search.codePoint: GlassGlyph.search,
  Icons.search_outlined.codePoint: GlassGlyph.search,
  Icons.music_note_outlined.codePoint: GlassGlyph.music,
  Icons.music_note_rounded.codePoint: GlassGlyph.music,
  Icons.open_in_full.codePoint: GlassGlyph.expand,
  Icons.open_in_new.codePoint: GlassGlyph.externalLink,
  Icons.pause.codePoint: GlassGlyph.pause,
  Icons.pause_rounded.codePoint: GlassGlyph.pause,
  Icons.phone_android.codePoint: GlassGlyph.phone,
  Icons.phone_android_outlined.codePoint: GlassGlyph.phone,
  Icons.play_arrow.codePoint: GlassGlyph.play,
  Icons.play_arrow_rounded.codePoint: GlassGlyph.play,
  Icons.play_circle_outline.codePoint: GlassGlyph.play,
  Icons.playlist_add.codePoint: GlassGlyph.playlist,
  Icons.qr_code_2.codePoint: GlassGlyph.qr,
  Icons.qr_code_scanner.codePoint: GlassGlyph.qr,
  Icons.refresh.codePoint: GlassGlyph.refresh,
  Icons.refresh_rounded.codePoint: GlassGlyph.refresh,
  Icons.save_alt.codePoint: GlassGlyph.save,
  Icons.skip_next.codePoint: GlassGlyph.next,
  Icons.skip_next_rounded.codePoint: GlassGlyph.next,
  Icons.skip_previous.codePoint: GlassGlyph.previous,
  Icons.skip_previous_rounded.codePoint: GlassGlyph.previous,
  Icons.star_border_rounded.codePoint: GlassGlyph.star,
  Icons.star_rounded.codePoint: GlassGlyph.star,
  Icons.stop.codePoint: GlassGlyph.stop,
  Icons.stop_circle_outlined.codePoint: GlassGlyph.stop,
  Icons.terminal.codePoint: GlassGlyph.terminal,
  Icons.terminal_outlined.codePoint: GlassGlyph.terminal,
  Icons.tune.codePoint: GlassGlyph.tune,
  Icons.tune_outlined.codePoint: GlassGlyph.tune,
  Icons.unfold_less.codePoint: GlassGlyph.collapse,
  Icons.unfold_more.codePoint: GlassGlyph.expand,
  Icons.visibility_outlined.codePoint: GlassGlyph.visibility,
  Icons.vpn_key_outlined.codePoint: GlassGlyph.key,
};

/// A semantic mark drawn entirely from the same rounded dot cell.
class GlassGlyphMark extends StatelessWidget {
  const GlassGlyphMark({
    super.key,
    required this.glyph,
    required this.size,
    this.color,
    this.motionController,
  });

  final GlassGlyph glyph;
  final double size;
  final Color? color;
  final GlassMotionController? motionController;

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _GlassGlyphPainter(
          glyph: glyph,
          color: color ?? tokens.ink,
          tokens: tokens,
          motionController: motionController,
        ),
      ),
    );
  }
}

class _GlassGlyphPainter extends CustomPainter {
  _GlassGlyphPainter({
    required this.glyph,
    required this.color,
    required this.tokens,
    required this.motionController,
  }) : super(repaint: motionController);

  final GlassGlyph glyph;
  final Color color;
  final GlassDesignTokens tokens;
  final GlassMotionController? motionController;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 32;
    if (!scale.isFinite || scale <= 0) return;
    final inset = Offset(
      (size.width - 32 * scale) / 2,
      (size.height - 32 * scale) / 2,
    );
    canvas.save();
    canvas.translate(inset.dx, inset.dy);
    canvas.scale(scale);
    final motion = motionController;
    if (motion != null) {
      final sample = motion.sample;
      final haloPaths = List<Path>.generate(4, (_) => Path());
      final corePaths = List<Path>.generate(8, (_) => Path());
      final haloCounts = List<int>.filled(haloPaths.length, 0);
      final coreCounts = List<int>.filled(corePaths.length, 0);
      for (final dot in sample.dots) {
        if (dot.opacity <= 0) continue;
        final cellRect = Rect.fromCenter(
          center: dot.position,
          width: GlassDesignTokens.glyphCellSize,
          height: GlassDesignTokens.glyphCellSize,
        );
        final core = RRect.fromRectAndRadius(
          cellRect,
          const Radius.circular(GlassDesignTokens.glyphCornerRadius),
        );
        final haloRect = cellRect.inflate(
          GlassDesignTokens.glyphFeather + GlassDesignTokens.glyphOuterHalo,
        );
        final haloBand = (dot.opacity * (haloPaths.length - 1)).round().clamp(
          0,
          haloPaths.length - 1,
        );
        haloPaths[haloBand].addRRect(
          RRect.fromRectAndRadius(
            haloRect,
            const Radius.circular(GlassDesignTokens.glyphCornerRadius),
          ),
        );
        haloCounts[haloBand]++;
        final coreBand = (dot.opacity * (corePaths.length - 1)).round().clamp(
          0,
          corePaths.length - 1,
        );
        corePaths[coreBand].addRRect(core);
        coreCounts[coreBand]++;
      }
      for (var band = 0; band < haloPaths.length; band++) {
        if (haloCounts[band] == 0) continue;
        canvas.drawPath(
          haloPaths[band],
          Paint()
            ..color = color.withValues(
              alpha:
                  GlassDesignTokens.glyphHaloAlpha *
                  ((band + 1) / haloPaths.length) *
                  (1 + sample.energy * .22),
            )
            ..maskFilter = const MaskFilter.blur(
              BlurStyle.normal,
              GlassDesignTokens.glyphFeather,
            ),
        );
      }
      for (var band = 0; band < corePaths.length; band++) {
        if (coreCounts[band] == 0) continue;
        canvas.drawPath(
          corePaths[band],
          Paint()
            ..color = color.withValues(
              alpha: .96 * (band + 1) / corePaths.length,
            ),
        );
      }
      canvas.restore();
      return;
    }

    final geometry = _GlyphGeometryCache.get(glyph);
    canvas.drawPath(
      geometry.halo,
      Paint()
        ..color = color.withValues(alpha: GlassDesignTokens.glyphHaloAlpha)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          GlassDesignTokens.glyphFeather,
        ),
    );
    canvas.drawPath(
      geometry.core,
      Paint()..color = color.withValues(alpha: .96),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      color != oldDelegate.color ||
      tokens != oldDelegate.tokens ||
      motionController != oldDelegate.motionController;
}

class _GlyphGeometry {
  const _GlyphGeometry({
    required this.core,
    required this.halo,
    required this.points,
  });

  final Path core;
  final Path halo;
  final List<Offset> points;
}

/// Geometry only; the cache is bounded by [GlassGlyph]'s finite enum and owns
/// no engine resources, textures, or per-widget shader instances.
abstract final class _GlyphGeometryCache {
  static final Map<GlassGlyph, _GlyphGeometry> _entries = {};

  static _GlyphGeometry get(GlassGlyph glyph) =>
      _entries.putIfAbsent(glyph, () => _create(glyph));

  static _GlyphGeometry _create(GlassGlyph glyph) {
    final rows = _rowsFor(glyph);
    final core = Path();
    final halo = Path();
    final points = <Offset>[];
    for (var row = 0; row < rows.length; row++) {
      final pattern = rows[row];
      for (var column = 0; column < pattern.length; column++) {
        if (pattern.codeUnitAt(column) != 49) continue;
        final centerX = 4 + column * GlassDesignTokens.glyphPitch;
        final centerY = 4 + row * GlassDesignTokens.glyphPitch;
        points.add(Offset(centerX, centerY));
        final coreHalf = GlassDesignTokens.glyphCellSize / 2;
        final coreRect = Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: GlassDesignTokens.glyphCellSize,
          height: GlassDesignTokens.glyphCellSize,
        );
        core.addRRect(
          RRect.fromRectAndRadius(
            coreRect,
            const Radius.circular(GlassDesignTokens.glyphCornerRadius),
          ),
        );
        final haloRect = coreRect.inflate(
          GlassDesignTokens.glyphFeather + GlassDesignTokens.glyphOuterHalo,
        );
        halo.addRRect(
          RRect.fromRectAndRadius(
            haloRect,
            Radius.circular(
              math.min(
                coreHalf,
                GlassDesignTokens.glyphCornerRadius +
                    GlassDesignTokens.glyphFeather +
                    GlassDesignTokens.glyphOuterHalo,
              ),
            ),
          ),
        );
      }
    }
    return _GlyphGeometry(
      core: core,
      halo: halo,
      points: List.unmodifiable(points),
    );
  }
}

List<String> _rowsFor(GlassGlyph glyph) => switch (glyph) {
  GlassGlyph.play => _GlyphRows.play,
  GlassGlyph.pause => _GlyphRows.pause,
  GlassGlyph.next => _GlyphRows.next,
  GlassGlyph.previous => _GlyphRows.previous,
  GlassGlyph.plus => _GlyphRows.plus,
  GlassGlyph.stop => _GlyphRows.stop,
  GlassGlyph.copy => _GlyphRows.copy,
  GlassGlyph.paste => _GlyphRows.paste,
  GlassGlyph.save => _GlyphRows.save,
  GlassGlyph.terminal => _GlyphRows.terminal,
  GlassGlyph.check => _GlyphRows.check,
  GlassGlyph.close => _GlyphRows.close,
  GlassGlyph.search => _GlyphRows.search,
  GlassGlyph.refresh => _GlyphRows.refresh,
  GlassGlyph.music => _GlyphRows.music,
  GlassGlyph.grid => _GlyphRows.grid,
  GlassGlyph.network => _GlyphRows.network,
  GlassGlyph.activity => _GlyphRows.activity,
  GlassGlyph.settings => _GlyphRows.settings,
  GlassGlyph.link => _GlyphRows.link,
  GlassGlyph.trash => _GlyphRows.trash,
  GlassGlyph.export => _GlyphRows.export,
  GlassGlyph.shield => _GlyphRows.shield,
  GlassGlyph.list => _GlyphRows.list,
  GlassGlyph.folder => _GlyphRows.folder,
  GlassGlyph.star => _GlyphRows.star,
  GlassGlyph.arrow => _GlyphRows.arrow,
  GlassGlyph.arrowBack => _GlyphRows.arrowBack,
  GlassGlyph.arrowUp => _GlyphRows.arrowUp,
  GlassGlyph.arrowDown => _GlyphRows.arrowDown,
  GlassGlyph.filter => _GlyphRows.filter,
  GlassGlyph.brightness => _GlyphRows.star,
  GlassGlyph.build || GlassGlyph.tune => _GlyphRows.settings,
  GlassGlyph.chat || GlassGlyph.account => _GlyphRows.chat,
  GlassGlyph.device || GlassGlyph.desktop => _GlyphRows.device,
  GlassGlyph.phone => _GlyphRows.phone,
  GlassGlyph.lock || GlassGlyph.key => _GlyphRows.shield,
  GlassGlyph.document || GlassGlyph.data => _GlyphRows.document,
  GlassGlyph.externalLink => _GlyphRows.externalLink,
  GlassGlyph.hourglass => _GlyphRows.hourglass,
  GlassGlyph.inbox => _GlyphRows.folder,
  GlassGlyph.history => _GlyphRows.activity,
  GlassGlyph.info => _GlyphRows.info,
  GlassGlyph.error => _GlyphRows.error,
  GlassGlyph.qr => _GlyphRows.qr,
  GlassGlyph.code => _GlyphRows.data,
  GlassGlyph.visibility => _GlyphRows.visibility,
  GlassGlyph.flash => _GlyphRows.flash,
  GlassGlyph.chevron => _GlyphRows.chevron,
  GlassGlyph.playlist => _GlyphRows.playlist,
  GlassGlyph.expand => _GlyphRows.expand,
  GlassGlyph.collapse => _GlyphRows.collapse,
  GlassGlyph.appearance => _GlyphRows.brightness,
};

abstract final class _GlyphRows {
  static const play = [
    '001000000',
    '001100000',
    '001110000',
    '001111000',
    '001111100',
    '001111000',
    '001110000',
    '001100000',
    '001000000',
  ];
  static const pause = [
    '011000110',
    '011000110',
    '011000110',
    '011000110',
    '011000110',
    '011000110',
    '011000110',
    '011000110',
    '011000110',
  ];
  static const next = [
    '010000010',
    '011000010',
    '011100010',
    '011110010',
    '011111010',
    '011110010',
    '011100010',
    '011000010',
    '010000010',
  ];
  static const previous = [
    '010000010',
    '010000110',
    '010001110',
    '010011110',
    '010111110',
    '010011110',
    '010001110',
    '010000110',
    '010000010',
  ];
  static const plus = [
    '000010000',
    '000010000',
    '000010000',
    '000010000',
    '111111111',
    '000010000',
    '000010000',
    '000010000',
    '000010000',
  ];
  static const stop = [
    '000000000',
    '011111110',
    '011111110',
    '011111110',
    '011111110',
    '011111110',
    '011111110',
    '011111110',
    '000000000',
  ];
  static const copy = [
    '001111110',
    '001000010',
    '111110010',
    '100010010',
    '100010010',
    '100011110',
    '100010000',
    '100010000',
    '111110000',
  ];
  static const paste = [
    '000010000',
    '000111000',
    '001010100',
    '000010000',
    '011111110',
    '010000010',
    '010111010',
    '010101010',
    '011111110',
  ];
  static const save = [
    '111111110',
    '101001010',
    '101111010',
    '100000010',
    '100000010',
    '101111010',
    '101001010',
    '101001010',
    '111111110',
  ];
  static const terminal = [
    '000000000',
    '010000000',
    '001000000',
    '000100000',
    '001000000',
    '010000000',
    '000011110',
    '000000000',
    '000000000',
  ];
  static const check = [
    '000000001',
    '000000010',
    '000000100',
    '000001000',
    '100010000',
    '010100000',
    '001000000',
    '000000000',
    '000000000',
  ];
  static const close = [
    '100000001',
    '010000010',
    '001000100',
    '000101000',
    '000010000',
    '000101000',
    '001000100',
    '010000010',
    '100000001',
  ];
  static const search = [
    '001111000',
    '010000100',
    '100000010',
    '100000010',
    '100000010',
    '010000100',
    '001111100',
    '000000010',
    '000000001',
  ];
  static const refresh = [
    '001111000',
    '010000100',
    '100000010',
    '100000111',
    '100000000',
    '111000001',
    '010000001',
    '001000010',
    '000111100',
  ];
  static const music = [
    '000011110',
    '000010010',
    '000010010',
    '000010010',
    '000010010',
    '001110110',
    '011101110',
    '011001100',
    '000000000',
  ];
  static const grid = [
    '111000111',
    '101000101',
    '111000111',
    '000000000',
    '000000000',
    '000000000',
    '111000111',
    '101000101',
    '111000111',
  ];
  static const network = [
    '000111000',
    '000101000',
    '000111000',
    '000010000',
    '001111100',
    '001000100',
    '111000111',
    '101000101',
    '111000111',
  ];
  static const activity = [
    '000000000',
    '000010000',
    '000111000',
    '001101100',
    '111000111',
    '000000000',
    '000000000',
    '000000000',
    '000000000',
  ];
  static const settings = [
    '000111000',
    '010101010',
    '001111100',
    '111000111',
    '101010101',
    '111000111',
    '001111100',
    '010101010',
    '000111000',
  ];
  static const link = [
    '001110000',
    '010001000',
    '100010000',
    '100110000',
    '011011110',
    '000110001',
    '000010001',
    '000100010',
    '000011100',
  ];
  static const trash = [
    '000111000',
    '011111110',
    '000000000',
    '010101010',
    '010101010',
    '010101010',
    '010101010',
    '010000010',
    '001111100',
  ];
  static const export = [
    '000010000',
    '000111000',
    '001010100',
    '010010010',
    '000010000',
    '100010001',
    '100000001',
    '100000001',
    '111111111',
  ];
  static const shield = [
    '000010000',
    '011101110',
    '010000010',
    '010010010',
    '010111010',
    '010010010',
    '001000100',
    '000101000',
    '000010000',
  ];
  static const list = [
    '110111111',
    '000000000',
    '000000000',
    '110111111',
    '000000000',
    '000000000',
    '110111111',
    '000000000',
    '000000000',
  ];
  static const folder = [
    '111100000',
    '100110000',
    '100011111',
    '100000001',
    '100000001',
    '100000001',
    '100000001',
    '111111111',
    '000000000',
  ];
  static const star = [
    '000010000',
    '000010000',
    '001111100',
    '111101111',
    '011111110',
    '001111100',
    '001101100',
    '010000010',
    '100000001',
  ];
  static const arrow = [
    '000010000',
    '000001000',
    '000000100',
    '111111110',
    '000000100',
    '000001000',
    '000010000',
    '000000000',
    '000000000',
  ];
  static const arrowBack = [
    '000010000',
    '000100000',
    '001000000',
    '111111110',
    '001000000',
    '000100000',
    '000010000',
    '000000000',
    '000000000',
  ];
  static const arrowUp = [
    '000010000',
    '000111000',
    '001010100',
    '010010010',
    '000010000',
    '000010000',
    '000010000',
    '000000000',
    '000000000',
  ];
  static const arrowDown = [
    '000010000',
    '000010000',
    '000010000',
    '010010010',
    '001010100',
    '000111000',
    '000010000',
    '000000000',
    '000000000',
  ];
  static const filter = [
    '111111111',
    '010000010',
    '001000100',
    '000101000',
    '000010000',
    '000010000',
    '000010000',
    '000010000',
    '000000000',
  ];
  static const chat = [
    '001111100',
    '010000010',
    '100000001',
    '100000001',
    '100000001',
    '010000010',
    '001111100',
    '000100000',
    '001000000',
  ];
  static const device = [
    '111111111',
    '100000001',
    '101110101',
    '101010101',
    '101110101',
    '100000001',
    '100000001',
    '111111111',
    '000010000',
  ];
  static const phone = [
    '001111100',
    '001000100',
    '001000100',
    '001000100',
    '001000100',
    '001000100',
    '001000100',
    '001000100',
    '001111100',
  ];
  static const document = [
    '011111100',
    '010000100',
    '010110100',
    '010110100',
    '010000100',
    '010110100',
    '010110100',
    '010000100',
    '011111100',
  ];
  static const externalLink = [
    '000000111',
    '000000101',
    '000000101',
    '000001001',
    '000010001',
    '111100001',
    '100000001',
    '100000001',
    '111111111',
  ];
  static const hourglass = [
    '111111111',
    '000000000',
    '001111100',
    '000111000',
    '000010000',
    '000111000',
    '001111100',
    '000000000',
    '111111111',
  ];
  static const info = [
    '001111100',
    '010000010',
    '100000001',
    '000111000',
    '000010000',
    '000010000',
    '000010000',
    '010000010',
    '001111100',
  ];
  static const error = [
    '001111100',
    '010000010',
    '100110001',
    '100110001',
    '100000001',
    '100000001',
    '100110001',
    '010000010',
    '001111100',
  ];
  static const qr = [
    '111000111',
    '101000101',
    '111000111',
    '000000000',
    '001110100',
    '000101000',
    '111000111',
    '101000101',
    '111000111',
  ];
  static const data = [
    '011000110',
    '001001100',
    '000111000',
    '000010000',
    '000111000',
    '001001100',
    '011000110',
    '000000000',
    '000000000',
  ];
  static const visibility = [
    '000000000',
    '001111100',
    '010000010',
    '100110001',
    '101001101',
    '100110001',
    '010000010',
    '001111100',
    '000000000',
  ];
  static const chevron = [
    '100000000',
    '010000000',
    '001000000',
    '000100000',
    '000010000',
    '000100000',
    '001000000',
    '010000000',
    '100000000',
  ];
  static const playlist = [
    '110000000',
    '110111111',
    '110000000',
    '110111111',
    '110000000',
    '110111111',
    '110000000',
    '000000000',
    '000000000',
  ];
  static const expand = [
    '110000011',
    '110000011',
    '000000000',
    '000000000',
    '000000000',
    '000000000',
    '110000011',
    '110000011',
    '000000000',
  ];
  static const collapse = [
    '000000000',
    '011000110',
    '011000110',
    '000000000',
    '000000000',
    '011000110',
    '011000110',
    '000000000',
    '000000000',
  ];
  static const brightness = [
    '000010000',
    '010010010',
    '001111100',
    '101111101',
    '001111100',
    '010010010',
    '000010000',
    '000000000',
    '000000000',
  ];
  static const flash = [
    '000001100',
    '000011000',
    '000110000',
    '001111000',
    '000011100',
    '000001100',
    '000011000',
    '000110000',
    '000000000',
  ];
}
