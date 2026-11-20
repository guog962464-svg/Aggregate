import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'glass_design_tokens.dart';
import 'glass_glyph.dart';
import 'glass_motion.dart';
import 'glass_optic_renderer.dart';

const _themeSwitchSunLight = Color(0xFFFFA82E);

enum GlassButtonKind {
  primary,
  secondary,
  icon,
  playback,
  navigation,
  segmented,
  danger,
}

enum GlassButtonSize {
  primary,
  secondary,
  compactAction,
  directory,
  navigation,
  connectionNavigation,
  icon,
  playback,
  reference,
}

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
    this.trailing,
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
  final Widget? trailing;
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
  ui.FragmentShader? _surfaceShader;
  ui.Image? _shaderSampler;
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
    _loadSurfaceShader();
  }

  Future<void> _loadSurfaceShader() async {
    try {
      final program = await GlassOpticRenderer.loadProgram();
      if (!mounted) return;
      final shader = program.fragmentShader();
      setState(() {
        _surfaceShader = shader;
        _shaderSampler = GlassOpticRenderer.transparentSampler;
      });
    } on Object {
      // Keep the painter's complete vector fallback if runtime effects are not
      // available in the current test or rendering environment.
    }
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
    _surfaceShader?.dispose();
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
        widget.size == GlassButtonSize.compactAction ||
        widget.size == GlassButtonSize.directory ||
        widget.size == GlassButtonSize.navigation ||
        widget.size == GlassButtonSize.connectionNavigation ||
        widget.size == GlassButtonSize.icon ||
        widget.size == GlassButtonSize.playback;
    final padding = widget.iconOnly
        ? EdgeInsets.zero
        : EdgeInsets.symmetric(horizontal: small ? 12 : 16);
    final content = _buildContent(
      tokens,
      height,
      underlay: theme.colorScheme.surface,
    );
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
      shadowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.shadow;
        final accent = widget.kind == GlassButtonKind.danger
            ? tokens.danger
            : tokens.daylight > .5
            ? _themeSwitchSunLight
            : tokens.glow;
        final halo = accent.withValues(alpha: tokens.daylight > .5 ? .38 : .42);
        final blend = states.contains(WidgetState.pressed)
            ? .32
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.selected)
            ? .20
            : widget.kind == GlassButtonKind.navigation ||
                  widget.kind == GlassButtonKind.segmented
            ? .04
            : .12;
        return Color.lerp(tokens.shadow, halo, blend)!;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0;
        if (states.contains(WidgetState.pressed)) return 1.8;
        if (states.contains(WidgetState.hovered)) return 7.5;
        if (widget.kind == GlassButtonKind.navigation ||
            widget.kind == GlassButtonKind.segmented) {
          return states.contains(WidgetState.selected) ? 4.5 : 1.5;
        }
        return 5.5;
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
          shader: _surfaceShader,
          sampler: _shaderSampler,
          displayRatio: MediaQuery.devicePixelRatioOf(context),
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

  Widget _buildContent(
    GlassDesignTokens tokens,
    double height, {
    required Color underlay,
  }) {
    final muted = !_enabled || widget.busy;
    // Keep supporting copy subdued while protecting it against intermediate
    // glass tones produced by the live theme transition.
    final supportingTextBlend = .45 + tokens.daylight * .25;
    final labelAppearance = _readableGlassLabelAppearance(
      tokens.text,
      tokens,
      underlay: underlay,
      translucent: muted,
      gradientPosition: .5,
    );
    final descriptionAppearance = _readableGlassLabelAppearance(
      Color.lerp(tokens.muted, tokens.text, supportingTextBlend)!,
      tokens,
      underlay: underlay,
      translucent: muted,
      gradientPosition: .56,
    );
    final sourceAppearance = _readableGlassLabelAppearance(
      Color.lerp(tokens.muted, tokens.text, supportingTextBlend)!,
      tokens,
      underlay: underlay,
      translucent: muted,
      gradientPosition: 1,
    );
    final dangerLabelAppearance = _readableGlassLabelAppearance(
      tokens.danger,
      tokens,
      underlay: underlay,
      translucent: muted,
      gradientPosition: .5,
      targetContrast: 6.0,
    );
    final labelColor = widget.kind == GlassButtonKind.danger
        ? dangerLabelAppearance.color
        : labelAppearance.color;
    final labelShadows = widget.kind == GlassButtonKind.danger
        ? dangerLabelAppearance.shadows
        : labelAppearance.shadows;
    final iconSize = switch (widget.size) {
      GlassButtonSize.reference => 32.0,
      GlassButtonSize.primary => 22.0,
      GlassButtonSize.compactAction => 20.0,
      GlassButtonSize.navigation ||
      GlassButtonSize.connectionNavigation => 16.0,
      GlassButtonSize.secondary ||
      GlassButtonSize.directory ||
      GlassButtonSize.icon ||
      GlassButtonSize.playback => 20.0,
    };
    final visibleLabel = widget.label ?? widget.semanticsLabel!;
    // Keep status cues on the glyph and face while preserving label contrast.
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
                      color: labelColor,
                      shadows: labelShadows,
                      fontWeight: FontWeight.w600,
                      fontSize:
                          widget.size == GlassButtonSize.directory ||
                              widget.size == GlassButtonSize.navigation ||
                              widget.size ==
                                  GlassButtonSize.connectionNavigation ||
                              widget.size == GlassButtonSize.compactAction
                          ? 12
                          : 13,
                    ),
                  ),
                  if (widget.description case final description?)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: descriptionAppearance.color,
                        shadows: descriptionAppearance.shadows,
                        fontSize: widget.size == GlassButtonSize.directory
                            ? 10
                            : 11,
                      ),
                    ),
                  if (widget.source case final source?)
                    Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sourceAppearance.color,
                        shadows: sourceAppearance.shadows,
                        fontSize: widget.size == GlassButtonSize.directory
                            ? 9
                            : 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.trailing case final trailing?) ...[
            const SizedBox(width: 8),
            trailing,
          ],
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
                color: labelColor,
                shadows: labelShadows,
                fontWeight: widget.kind == GlassButtonKind.primary
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize:
                    widget.size == GlassButtonSize.compactAction ||
                        widget.size == GlassButtonSize.navigation ||
                        widget.size == GlassButtonSize.connectionNavigation
                    ? 12
                    : 13,
              ),
            ),
          ),
        ),
        if (widget.trailing case final trailing?) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }
}

double _heightFor(GlassButtonSize size) => switch (size) {
  GlassButtonSize.primary => GlassDesignTokens.primaryHeight,
  GlassButtonSize.secondary => GlassDesignTokens.secondaryHeight,
  GlassButtonSize.compactAction => 40,
  GlassButtonSize.directory => 58,
  GlassButtonSize.navigation => 38,
  GlassButtonSize.connectionNavigation => 40,
  GlassButtonSize.icon => GlassDesignTokens.iconButtonSize,
  GlassButtonSize.playback => GlassDesignTokens.iconButtonSize,
  GlassButtonSize.reference => GlassDesignTokens.referenceHeight,
};

double _radiusFor(GlassButtonSize size) => switch (size) {
  GlassButtonSize.primary => 16,
  GlassButtonSize.reference => 22,
  GlassButtonSize.secondary => 13,
  GlassButtonSize.compactAction => 12,
  GlassButtonSize.directory => 11,
  GlassButtonSize.navigation => 11,
  GlassButtonSize.connectionNavigation => 11,
  GlassButtonSize.icon || GlassButtonSize.playback => 14,
};

_GlassLabelAppearance _readableGlassLabelAppearance(
  Color preferred,
  GlassDesignTokens tokens, {
  required Color underlay,
  required bool translucent,
  required double gradientPosition,
  double targetContrast = 5.1,
}) {
  var opaqueSurface = Color.lerp(
    tokens.glassTop,
    tokens.glassBottom,
    gradientPosition,
  )!;
  if (gradientPosition > .72) {
    final insetAlpha =
        GlassDesignTokens.restingButtonInsetOpacity *
        ((gradientPosition - .72) / .28);
    opaqueSurface = Color.alphaBlend(
      tokens.inset.withValues(alpha: insetAlpha),
      opaqueSurface,
    );
  }
  final surface = translucent
      ? Color.alphaBlend(
          opaqueSurface.withValues(
            alpha: GlassDesignTokens.disabledButtonFaceOpacity,
          ),
          underlay,
        )
      : opaqueSurface;
  if (_buttonContrastRatio(preferred, surface) >= targetContrast) {
    return (color: preferred, shadows: null);
  }
  final blackContrast = _buttonContrastRatio(Colors.black, surface);
  final whiteContrast = _buttonContrastRatio(Colors.white, surface);
  // A disabled face composites against the page surface; keep the white
  // side through the gray crossover so black takes over with a safer margin.
  final preferWhite = translucent
      ? whiteContrast >= 4.0
      : whiteContrast > blackContrast;
  final target = preferWhite ? Colors.white : Colors.black;
  final achievableContrast = preferWhite ? whiteContrast : blackContrast;
  if (achievableContrast < targetContrast) {
    return (
      color: target,
      shadows: achievableContrast < 4.9 ? _buttonTextHalo(target) : null,
    );
  }

  var lower = 0.0;
  var upper = 1.0;
  for (var iteration = 0; iteration < 12; iteration++) {
    final middle = (lower + upper) / 2;
    final candidate = Color.lerp(preferred, target, middle)!;
    if (_buttonContrastRatio(candidate, surface) >= targetContrast) {
      upper = middle;
    } else {
      lower = middle;
    }
  }
  return (color: Color.lerp(preferred, target, upper)!, shadows: null);
}

List<Shadow> _buttonTextHalo(Color foreground) {
  final halo = foreground == Colors.white ? Colors.black : Colors.white;
  const offsets = [
    Offset(-1, -1),
    Offset(0, -1),
    Offset(1, -1),
    Offset(-1, 0),
    Offset(1, 0),
    Offset(-1, 1),
    Offset(0, 1),
    Offset(1, 1),
  ];
  return [for (final offset in offsets) Shadow(color: halo, offset: offset)];
}

typedef _GlassLabelAppearance = ({Color color, List<Shadow>? shadows});

double _buttonContrastRatio(Color foreground, Color background) {
  final foregroundLuminance = Color.alphaBlend(
    foreground,
    background,
  ).computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _GlassButtonSurfacePainter extends CustomPainter {
  _GlassButtonSurfacePainter({
    required this.tokens,
    required this.kind,
    required this.motion,
    required this.shader,
    required this.sampler,
    required this.displayRatio,
    required this.states,
    required this.radius,
  }) : super(repaint: motion.surfaceMotion);

  final GlassDesignTokens tokens;
  final GlassButtonKind kind;
  final GlassMotionController motion;
  final ui.FragmentShader? shader;
  final ui.Image? sampler;
  final double displayRatio;
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
    final isNavigation =
        kind == GlassButtonKind.navigation || kind == GlassButtonKind.segmented;
    final materialWeight = isNavigation ? .74 : 1.0;
    final isDaylight = tokens.daylight > .5;
    final accent = kind == GlassButtonKind.danger
        ? tokens.danger
        : isDaylight
        ? _themeSwitchSunLight
        : tokens.glow;
    final opacity = isDisabled
        ? GlassDesignTokens.disabledButtonFaceOpacity
        : 1.0;
    final darkAmount = math
        .pow((1 - tokens.daylight).clamp(0.0, 1.0), 2.5)
        .toDouble();
    final darkSurfaceBlend = .80 * darkAmount;
    final darkInsetBlend = .40 * darkAmount;
    final surfaceReflectance = .55 + tokens.daylight * .45;
    final edgeReflectance = .34 + tokens.daylight * .66;
    final glassTop = Color.lerp(
      tokens.glassTop,
      tokens.surface,
      darkSurfaceBlend,
    )!;
    final glassBottom = Color.lerp(
      tokens.glassBottom,
      tokens.inset,
      darkInsetBlend,
    )!;
    final motionEnergy = motion.energy;
    final time = motion.now.inMicroseconds / Duration.microsecondsPerSecond;
    final animated = motion.animationsEnabled && !isDisabled;
    final phase = animated
        ? time * (math.pi * 2 / 9.2) + motion.phaseSeed * .37
        : math.pi * .45;
    final breath = animated ? .5 + .5 * math.sin(phase) : .5;
    final lightDrift = animated ? math.sin(phase) * radius * .12 : 0.0;
    final lightAlignment = Alignment(
      (isDaylight ? .82 : -.82) +
          (isDaylight ? lightDrift : -lightDrift) / math.max(size.width, 1),
      (isDaylight ? -.74 : .74) +
          math.cos(phase * .8) * (isDaylight ? .035 : -.035),
    );
    final restingLightStrength = isNavigation
        ? isSelected
              ? .46
              : .14
        : (isSelected || kind == GlassButtonKind.primary)
        ? .62
        : .36;
    final lightStrength = isDisabled
        ? .025
        : isPressed
        ? .88
        : isHovered
        ? .68
        : restingLightStrength +
              breath * (isNavigation ? .025 : .06) +
              motionEnergy * .22;
    final emitterGlowWidth = math.min(12.0, math.max(6.0, size.height * .12));
    final emitterBlur = math.min(5.0, math.max(3.0, size.height * .05));
    final emitterCoreWidth = math.min(2.4, math.max(1.6, size.height * .025));
    final emitterHighlightWidth = math.min(
      1.1,
      math.max(.8, size.height * .011),
    );

    final usesSharedShader = shader != null && sampler != null;
    if (usesSharedShader) {
      GlassOpticRenderer.paintActionLens(
        canvas: canvas,
        size: size,
        shader: shader!,
        sampler: sampler!,
        frame: GlassActionLensFrame(
          daylight: tokens.daylight,
          time: time,
          displayRatio: displayRatio,
          zoom: size.height / 198,
          radius: radius,
          energy: lightStrength * 1.89,
          angle: (isDaylight ? -.72 : 2.42) + math.sin(phase) * .045,
          refraction: 40,
          frost: .76,
          pixelGlow: .64,
          stripHalfAngle: .92,
          top: isPressed
              ? Color.lerp(tokens.glassTop, tokens.inset, .10)!
              : Color.alphaBlend(
                  tokens.highlight.withValues(
                    alpha: .08 * materialWeight * surfaceReflectance,
                  ),
                  glassTop,
                ),
          bottom: isPressed
              ? Color.lerp(tokens.glassBottom, tokens.inset, .30)!
              : glassBottom,
          inset: tokens.inset,
          accent: accent,
          opacity: opacity,
          pressed: isPressed,
          hovered: isHovered,
          disabled: isDisabled,
          selected: isSelected,
          navigation: isNavigation,
          primary: kind == GlassButtonKind.primary,
        ),
      );
    } else {
      // Keep a complete vector fallback while the shared runtime effect loads
      // or in renderers that do not support Flutter runtime effects.
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isPressed
                  ? Color.lerp(tokens.glassTop, tokens.inset, .10)!
                  : Color.alphaBlend(
                      tokens.highlight.withValues(
                        alpha: .08 * materialWeight * surfaceReflectance,
                      ),
                      glassTop,
                    ),
              Color.lerp(
                glassTop,
                isPressed ? tokens.inset : glassBottom,
                isPressed ? .64 : .34,
              )!,
              isPressed
                  ? Color.lerp(tokens.glassBottom, tokens.inset, .30)!
                  : glassBottom,
            ],
            stops: const [0, .38, 1],
          ).createShader(rect)
          ..color = Color.fromRGBO(255, 255, 255, opacity),
      );

      final inset = rect.deflate(1.35);
      if (inset.width > 0 && inset.height > 0) {
        final inner = RRect.fromRectAndRadius(
          inset,
          Radius.circular((radius - 1.35).clamp(0, radius)),
        );
        canvas.drawRRect(
          inner,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tokens.highlight.withValues(
                  alpha:
                      (isDisabled ? .34 : .68) *
                      materialWeight *
                      surfaceReflectance,
                ),
                Colors.white.withValues(
                  alpha: (isDisabled ? .02 : .06) * materialWeight,
                ),
                Colors.transparent,
                tokens.inset.withValues(
                  alpha: isPressed
                      ? .42
                      : GlassDesignTokens.restingButtonInsetOpacity *
                            (isNavigation ? .85 : 1.15),
                ),
              ],
              stops: const [0, .12, .72, 1],
            ).createShader(inset),
        );
      }

      canvas.save();
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(-.72, -.92),
            radius: 1.35,
            colors: [
              tokens.highlight.withValues(
                alpha:
                    (isDisabled ? .16 : .28) *
                    materialWeight *
                    surfaceReflectance,
              ),
              Colors.transparent,
            ],
            stops: const [0, 1],
          ).createShader(rect),
      );
      if (!isDisabled &&
          (animated || isPressed || isHovered || motionEnergy > 0)) {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: lightAlignment,
              radius: isReferenceSize ? 1.0 : .82,
              colors: [
                accent.withValues(
                  alpha:
                      (isPressed
                          ? .42
                          : isDaylight
                          ? .36 + breath * .06
                          : .22 + breath * .06) *
                      materialWeight,
                ),
                accent.withValues(
                  alpha: (isDaylight ? .17 : .08) * materialWeight,
                ),
                Colors.transparent,
              ],
              stops: const [0, .34, 1],
            ).createShader(rect),
        );
      }
      if (isSelected && !isPressed) {
        canvas.drawRRect(
          rrect,
          Paint()..color = accent.withValues(alpha: .075 * materialWeight),
        );
      }
      canvas.restore();
    }

    final rrectPath = Path()..addRRect(rrect);

    final upperBevel = Path()
      ..moveTo(
        math.max(radius * .82, size.width - radius * 3.1 + lightDrift),
        1.1,
      )
      ..cubicTo(
        size.width - radius * 2.15 + lightDrift,
        .35,
        size.width - radius * .35,
        .75,
        size.width - 1.0,
        radius * .86,
      );
    final lunarBevel = Path()
      ..moveTo(size.width * .58, size.height - 1.0)
      ..cubicTo(
        size.width * .30,
        size.height - .25,
        .8,
        size.height * .75,
        1.0,
        size.height * .48,
      );
    if (!usesSharedShader) {
      canvas.drawPath(
        upperBevel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isReferenceSize ? 4.2 : 3.2
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0)
          ..color = tokens.highlight.withValues(
            alpha:
                (isDisabled ? .08 : .22) * materialWeight * surfaceReflectance,
          ),
      );
      canvas.drawPath(
        upperBevel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPressed ? 1.2 : .8
          ..strokeCap = StrokeCap.round
          ..color = tokens.highlight.withValues(
            alpha:
                (isDisabled ? .2 : .62) * materialWeight * surfaceReflectance,
          ),
      );
      if (!isDisabled &&
          (animated || isPressed || isHovered || motionEnergy > 0)) {
        // Vector fallback for renderers that do not support runtime effects.
        final emitterBevel = isDaylight ? upperBevel : lunarBevel;
        canvas.drawPath(
          emitterBevel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = emitterGlowWidth
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, emitterBlur)
            ..color = accent.withValues(alpha: lightStrength * .62),
        );
        canvas.drawPath(
          emitterBevel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = emitterCoreWidth
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: lightStrength),
        );
        canvas.drawPath(
          emitterBevel,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = emitterHighlightWidth
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: lightStrength * .92),
        );
      }
    }

    final bevelRect = rect.deflate(.55);
    final bevel = RRect.fromRectAndRadius(
      bevelRect,
      Radius.circular((radius - .55).clamp(0, radius)),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawPath(
      rrectPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocused ? 1.8 : 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.highlight.withValues(
              alpha:
                  (isDisabled ? .26 : .72) * materialWeight * edgeReflectance,
            ),
            tokens.highlight.withValues(
              alpha: .20 * materialWeight * edgeReflectance,
            ),
            accent.withValues(
              alpha: (isDisabled ? .08 : lightStrength * .24) * edgeReflectance,
            ),
            tokens.inset.withValues(alpha: isPressed ? .66 : .24),
          ],
          stops: const [0, .36, .68, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      bevel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = tokens.inset.withValues(alpha: isPressed ? .38 : .12),
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
        ..color = tokens.inset.withValues(
          alpha: isDisabled ? .10 : (isPressed ? .38 : .23),
        ),
    );
    canvas.restore();

    final focusColor = isFocused ? tokens.focusRing : tokens.highlight;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocused ? 1.8 : .55
        ..color = focusColor.withValues(
          alpha: isFocused
              ? .98
              : (isDisabled ? .28 : .42) * materialWeight * edgeReflectance,
        ),
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
            ..color = tokens.focusRing.withValues(alpha: .54),
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
