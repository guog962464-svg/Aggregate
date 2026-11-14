import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'glass_design_tokens.dart';
import 'glass_glyph.dart';
import 'glass_motion.dart';

enum GlassButtonKind {
  primary,
  secondary,
  icon,
  playback,
  navigation,
  segmented,
  danger,
}

enum GlassButtonSize { primary, secondary, icon, playback, reference }

/// A platform-neutral action control. The caller owns the operation; this
/// module owns only button semantics, shared glass material, and dot glyphs.
class GlassActionButton extends StatefulWidget {
  const GlassActionButton({
    super.key,
    required this.glyph,
    required this.onPressed,
    this.label,
    this.busyLabel,
    this.description,
    this.source,
    this.semanticsLabel,
    this.kind = GlassButtonKind.secondary,
    this.size = GlassButtonSize.secondary,
    this.enabled = true,
    this.busy = false,
    this.selected = false,
    this.iconOnly = false,
    this.expand = false,
    this.focusNode,
    this.autofocus = false,
    this.motionPhaseSeed,
  }) : assert(label != null || semanticsLabel != null),
       assert(iconOnly || label != null);

  final GlassGlyph glyph;
  final String? label;
  final String? busyLabel;
  final String? description;
  final String? source;
  final String? semanticsLabel;
  final GlassButtonKind kind;
  final GlassButtonSize size;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool busy;
  final bool selected;
  final bool iconOnly;
  final bool expand;
  final FocusNode? focusNode;
  final bool autofocus;
  final int? motionPhaseSeed;

  @override
  State<GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<GlassActionButton> {
  late final WidgetStatesController _statesController;
  late final GlassMotionController _motionController;
  final GlobalKey _motionBoxKey = GlobalKey();
  late final void Function(Size previous, Size current)
  _visibilityViewportListener = _handleViewportSizeChanged;
  ScrollPosition? _scrollPosition;
  GlassMotionScopeState? _motionScope;
  Size? _lastMotionBoxSize;
  bool _visibilityCheckScheduled = false;
  bool _visible = true;
  bool _disableAnimations = false;

  bool get _enabled =>
      widget.enabled && !widget.busy && widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _motionController = GlassMotionController(
      initialGlyph: widget.glyph,
      phaseSeed: widget.motionPhaseSeed,
    );
    _statesController = WidgetStatesController()
      ..update(WidgetState.selected, widget.selected)
      ..update(WidgetState.disabled, !_enabled);
    _statesController.addListener(_handleVisualStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    final nextMotionScope = GlassMotionScope.maybeOf(context);
    if (_motionScope != nextMotionScope) {
      _motionScope?.removeVisibilityViewportListener(
        _visibilityViewportListener,
      );
      _motionScope?.removeSizeVisibilityCheck(_scheduleVisibilityCheck);
      _motionScope = nextMotionScope;
      _motionScope?.addVisibilityViewportListener(_visibilityViewportListener);
    }
    _updateScrollPosition();
    _syncMotion();
    _scheduleVisibilityCheck();
  }

  void _requestSizeVisibilityCheck() {
    final scope = _motionScope;
    if (scope == null) {
      _scheduleVisibilityCheck();
    } else {
      scope.scheduleSizeVisibilityCheck(_scheduleVisibilityCheck);
    }
  }

  @override
  void didUpdateWidget(covariant GlassActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glyph != widget.glyph) {
      _motionController.setGlyph(widget.glyph);
    }
    if (oldWidget.selected != widget.selected) {
      _statesController.update(WidgetState.selected, widget.selected);
    }
    if (_enabled !=
        (oldWidget.enabled && !oldWidget.busy && oldWidget.onPressed != null)) {
      _statesController.update(WidgetState.disabled, !_enabled);
    }
    _syncMotion();
  }

  void _syncMotion() {
    _motionController.configure(
      scope: _motionScope,
      visible: _visible,
      motionAllowed: _motionScope != null && !_disableAnimations && _enabled,
    );
  }

  void _handleVisualStateChanged() {
    final states = _statesController.value;
    _motionController.setInteraction(
      hovered: states.contains(WidgetState.hovered),
      focused: states.contains(WidgetState.focused),
    );
  }

  void _updateScrollPosition() {
    final position = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition == position) return;
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _scrollPosition = position;
    _scrollPosition?.addListener(_scheduleVisibilityCheck);
  }

  void _handleMotionBoxSizeChanged() {
    final renderObject = _motionBoxKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      final currentSize = renderObject.size;
      final previousSize = _lastMotionBoxSize;
      _lastMotionBoxSize = currentSize;
      final direction = _scrollPosition?.axisDirection;
      if (previousSize == null || direction == null) return;
      final visibilityAxisChanged = switch (direction) {
        AxisDirection.up ||
        AxisDirection.down => previousSize.height != currentSize.height,
        AxisDirection.left ||
        AxisDirection.right => previousSize.width != currentSize.width,
      };
      if (!visibilityAxisChanged) return;
    } else if (_scrollPosition == null) {
      return;
    }
    _requestSizeVisibilityCheck();
  }

  void _handleViewportSizeChanged(Size previous, Size current) {
    final visibilityAxisChanged = switch (_scrollPosition?.axisDirection) {
      AxisDirection.up ||
      AxisDirection.down => previous.height != current.height,
      AxisDirection.left ||
      AxisDirection.right => previous.width != current.width,
      null => false,
    };
    if (visibilityAxisChanged) _scheduleVisibilityCheck();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled || !mounted) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      final renderObject = _motionBoxKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        return;
      }
      _lastMotionBoxSize = renderObject.size;
      final maybeViewport = RenderAbstractViewport.maybeOf(renderObject);
      final RenderBox? viewportBox = maybeViewport is RenderBox
          ? maybeViewport as RenderBox
          : null;
      var visible = true;
      if (viewportBox != null && viewportBox.attached && viewportBox.hasSize) {
        final buttonRect = MatrixUtils.transformRect(
          renderObject.getTransformTo(viewportBox),
          renderObject.paintBounds,
        );
        visible = buttonRect.overlaps(Offset.zero & viewportBox.size);
      }
      if (visible == _visible) return;
      _visible = visible;
      _motionController.setVisible(visible);
    });
  }

  void _handlePressed() {
    _motionController.trigger();
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _motionScope?.removeVisibilityViewportListener(_visibilityViewportListener);
    _motionScope?.removeSizeVisibilityCheck(_scheduleVisibilityCheck);
    _statesController.removeListener(_handleVisualStateChanged);
    _statesController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final name = widget.semanticsLabel ?? widget.label!;
    final height = _heightFor(widget.size);
    final small =
        widget.size == GlassButtonSize.icon ||
        widget.size == GlassButtonSize.playback;
    final padding = widget.iconOnly
        ? EdgeInsets.zero
        : EdgeInsets.symmetric(horizontal: small ? 12 : 16);
    final content = _buildContent(tokens, height);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radiusFor(widget.size)),
    );
    final style = ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.muted;
        return tokens.text;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(tokens.shadow),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0;
        if (states.contains(WidgetState.pressed)) return 2.2;
        if (states.contains(WidgetState.hovered)) return 7;
        return 5;
      }),
      shape: WidgetStatePropertyAll(shape),
      side: const WidgetStatePropertyAll(BorderSide.none),
      padding: WidgetStatePropertyAll(padding),
      alignment: widget.expand ? Alignment.centerLeft : Alignment.center,
      minimumSize: WidgetStatePropertyAll(
        Size(widget.iconOnly ? height : 0, height),
      ),
      fixedSize: widget.iconOnly
          ? WidgetStatePropertyAll(Size.square(height))
          : null,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      animationDuration: Duration.zero,
      splashFactory: NoSplash.splashFactory,
      backgroundBuilder: (context, states, child) => CustomPaint(
        painter: _GlassButtonSurfacePainter(
          tokens: tokens,
          kind: widget.kind,
          motion: _motionController,
          // WidgetStatesController mutates its set in place, so a painter must
          // keep a snapshot for shouldRepaint to observe state transitions.
          states: Set.unmodifiable(states),
          radius: _radiusFor(widget.size),
        ),
        child: child,
      ),
    );

    return Semantics(
      label: name,
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      value: widget.busy ? widget.busyLabel ?? '正在处理' : null,
      liveRegion: widget.busy,
      onTap: _enabled ? _handlePressed : null,
      child: ExcludeSemantics(
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _scheduleVisibilityCheck();
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _scheduleVisibilityCheck();
              return false;
            },
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _handleMotionBoxSizeChanged();
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: RepaintBoundary(
                  key: _motionBoxKey,
                  child: SizedBox(
                    width: widget.expand ? double.infinity : null,
                    child: TextButton(
                      onPressed: _enabled ? _handlePressed : null,
                      focusNode: widget.focusNode,
                      autofocus: widget.autofocus,
                      statesController: _statesController,
                      style: style,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(GlassDesignTokens tokens, double height) {
    final iconSize = switch (widget.size) {
      GlassButtonSize.reference => 32.0,
      GlassButtonSize.primary => 22.0,
      GlassButtonSize.secondary ||
      GlassButtonSize.icon ||
      GlassButtonSize.playback => 20.0,
    };
    final muted = !_enabled || widget.busy;
    final visibleLabel = widget.label ?? widget.semanticsLabel!;
    final mark = GlassGlyphMark(
      glyph: widget.glyph,
      size: iconSize,
      motionController: _motionController,
      color: muted
          ? tokens.muted.withValues(alpha: .76)
          : widget.kind == GlassButtonKind.danger
          ? tokens.danger
          : tokens.ink,
    );
    if (widget.iconOnly) {
      return Center(child: mark);
    }
    if (widget.description != null || widget.source != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 10),
          Flexible(
            child: RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.busy
                        ? widget.busyLabel ?? '$visibleLabel中'
                        : visibleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted
                          ? tokens.muted
                          : widget.kind == GlassButtonKind.danger
                          ? tokens.danger
                          : tokens.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (widget.description case final description?)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.muted, fontSize: 11),
                    ),
                  if (widget.source case final source?)
                    Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.muted, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 8),
        Flexible(
          child: RepaintBoundary(
            child: Text(
              widget.busy ? widget.busyLabel ?? '$visibleLabel中' : visibleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted
                    ? tokens.muted
                    : widget.kind == GlassButtonKind.danger
                    ? tokens.danger
                    : tokens.text,
                fontWeight: widget.kind == GlassButtonKind.primary
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

double _heightFor(GlassButtonSize size) => switch (size) {
  GlassButtonSize.primary => GlassDesignTokens.primaryHeight,
  GlassButtonSize.secondary => GlassDesignTokens.secondaryHeight,
  GlassButtonSize.icon => GlassDesignTokens.iconButtonSize,
  GlassButtonSize.playback => GlassDesignTokens.iconButtonSize,
  GlassButtonSize.reference => GlassDesignTokens.referenceHeight,
};

double _radiusFor(GlassButtonSize size) => switch (size) {
  GlassButtonSize.primary => 16,
  GlassButtonSize.reference => 22,
  GlassButtonSize.secondary => 13,
  GlassButtonSize.icon || GlassButtonSize.playback => 14,
};

class _GlassButtonSurfacePainter extends CustomPainter {
  _GlassButtonSurfacePainter({
    required this.tokens,
    required this.kind,
    required this.motion,
    required this.states,
    required this.radius,
  }) : super(repaint: motion);

  final GlassDesignTokens tokens;
  final GlassButtonKind kind;
  final GlassMotionController motion;
  final Set<WidgetState> states;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final isDisabled = states.contains(WidgetState.disabled);
    final isPressed = states.contains(WidgetState.pressed);
    final isHovered = states.contains(WidgetState.hovered);
    final isFocused = states.contains(WidgetState.focused);
    final isSelected = states.contains(WidgetState.selected);
    final isReferenceSize = radius >= 22;
    final accent = kind == GlassButtonKind.danger ? tokens.danger : tokens.glow;
    final opacity = isDisabled ? .52 : 1.0;
    final motionEnergy = motion.energy;

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.glassTop,
            Color.lerp(tokens.glassTop, tokens.glassBottom, .42)!,
            tokens.glassBottom,
          ],
          stops: const [0, .38, 1],
        ).createShader(rect)
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );

    final inset = rect.deflate(1.0);
    if (inset.width > 0 && inset.height > 0) {
      final inner = RRect.fromRectAndRadius(
        inset,
        Radius.circular((radius - 1).clamp(0, radius)),
      );
      canvas.drawRRect(
        inner,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tokens.highlight.withValues(alpha: isDisabled ? .34 : .74),
              Colors.white.withValues(alpha: isDisabled ? .02 : .07),
              Colors.transparent,
              tokens.inset.withValues(alpha: isPressed ? .22 : .13),
            ],
            stops: const [0, .12, .72, 1],
          ).createShader(inset),
      );
    }

    final topGlow = kind == GlassButtonKind.primary || isSelected;
    if (topGlow || isHovered || isPressed || motionEnergy > 0) {
      final glowAlpha = isPressed
          ? .18
          : (isHovered
                ? .12
                : (isReferenceSize ? .20 : .11) + motionEnergy * .13);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(
              .82 - motionEnergy * .24,
              -.78 + motionEnergy * .12,
            ),
            radius: 1.08,
            colors: [
              accent.withValues(alpha: glowAlpha),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }

    final arc = Path()
      ..moveTo(size.width * .54, 1.1)
      ..cubicTo(
        size.width * .74,
        .5,
        size.width - 1.0,
        1.2,
        size.width - 1.0,
        radius * .82,
      );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isReferenceSize ? 4.2 : 3.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isReferenceSize ? 3.6 : 2.3,
        )
        ..color = accent.withValues(
          alpha: isDisabled
              ? .01
              : (kind == GlassButtonKind.primary
                        ? (isReferenceSize ? .62 : .46)
                        : .28) +
                    motionEnergy * .12,
        ),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .95
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            tokens.highlight.withValues(alpha: isDisabled ? .30 : .82),
            accent.withValues(
              alpha: isDisabled
                  ? .12
                  : kind == GlassButtonKind.primary
                  ? (isReferenceSize ? .98 : .92)
                  : .62,
            ),
            Colors.transparent,
          ],
          stops: const [0, .34, .82, 1],
        ).createShader(rect),
    );
    final contact = Path()
      ..moveTo(radius * .72, size.height - 1.1)
      ..quadraticBezierTo(
        size.width * .5,
        size.height + .7,
        size.width - radius * .72,
        size.height - 1.1,
      );
    canvas.drawPath(
      contact,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = tokens.inset.withValues(alpha: isDisabled ? .10 : .23),
    );
    canvas.restore();

    if (!isDisabled && (topGlow || isHovered || isPressed)) {
      final lowerArc = Path()
        ..moveTo(radius * .68, size.height - 1.4)
        ..cubicTo(
          size.width * .3,
          size.height - .6,
          size.width * .7,
          size.height - .6,
          size.width - radius * .68,
          size.height - 1.4,
        );
      final dark = tokens.daylight < .5;
      final glowAlpha = isPressed ? .66 : (isHovered ? .58 : .50);
      canvas.drawPath(
        lowerArc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
          ..color = accent.withValues(alpha: glowAlpha * (dark ? 1.0 : .28)),
      );
      canvas.drawPath(
        lowerArc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              accent.withValues(alpha: dark ? .96 : .28),
              Colors.transparent,
            ],
            stops: const [0, .5, 1],
          ).createShader(rect),
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocused ? 1.7 : 1.0
        ..color = isFocused
            ? accent.withValues(alpha: .94)
            : tokens.highlight.withValues(alpha: isDisabled ? .36 : .70),
    );

    if (isFocused) {
      final focusRect = rect.deflate(2.8);
      if (focusRect.width > 0 && focusRect.height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            focusRect,
            Radius.circular((radius - 2.8).clamp(0, radius)),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .7
            ..color = accent.withValues(alpha: .54),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlassButtonSurfacePainter oldDelegate) =>
      tokens != oldDelegate.tokens ||
      kind != oldDelegate.kind ||
      !_sameStates(states, oldDelegate.states) ||
      radius != oldDelegate.radius;
}

bool _sameStates(Set<WidgetState> left, Set<WidgetState> right) =>
    left.length == right.length && left.containsAll(right);
