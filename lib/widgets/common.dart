import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: FlyxColors.mutedFor(context),
                  ),
                ),
              const SizedBox(height: 3),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: emphasized
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            blurRadius: 28,
            spreadRadius: -20,
            offset: const Offset(0, 12),
            color: dark ? Colors.black54 : Colors.black12,
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: card,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!),
          ),
      ],
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.online, this.label});
  final bool online;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final statusColor = online
        ? FlyxColors.successFor(context)
        : FlyxColors.mutedFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: statusColor.withValues(alpha: .18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label ?? (online ? 'Online' : 'Offline'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: statusColor,
                ),
          ),
        ],
      ),
    );
  }
}

class MetricLabel extends StatelessWidget {
  const MetricLabel({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: FlyxColors.mutedFor(context),
              ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({super.key, required this.kind, this.blocked = false, this.size = 44});

  final DeviceKind kind;
  final bool blocked;
  final double size;

  IconData get icon => switch (kind) {
        DeviceKind.phone => Icons.smartphone_rounded,
        DeviceKind.laptop => Icons.laptop_mac_rounded,
        DeviceKind.tv => Icons.tv_rounded,
        DeviceKind.tablet => Icons.tablet_mac_rounded,
        DeviceKind.desktop => Icons.desktop_mac_rounded,
        DeviceKind.console => Icons.sports_esports_rounded,
        DeviceKind.unknown => Icons.devices_other_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final foreground = blocked
        ? FlyxColors.dangerFor(context)
        : FlyxColors.accentFor(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * .48, color: foreground),
    );
  }
}

class LiveSparkline extends StatelessWidget {
  const LiveSparkline({super.key, required this.values, this.height = 62});
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          values,
          Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = math.max(1.0, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minValue) / range * (size.height - 8)) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: .27),
          color.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class UsageBars extends StatefulWidget {
  const UsageBars({super.key, required this.points, this.height = 142});

  final List<UsagePoint> points;
  final double height;

  @override
  State<UsageBars> createState() => _UsageBarsState();
}

class _UsageBarsState extends State<UsageBars> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant UsageBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex != null &&
        _selectedIndex! >= widget.points.length - 1) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text('Usage history will appear here as it is collected.'),
        ),
      );
    }

    final maxBytes = points.map((p) => p.bytes).reduce(math.max).toDouble();
    final selected =
        _selectedIndex == null ? null : points[_selectedIndex!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < points.length; index++)
                Expanded(
                  child: _UsageBar(
                    point: points[index],
                    maxBytes: maxBytes,
                    chartHeight: widget.height,
                    selected: _selectedIndex == index,
                    interactive: index < points.length - 1,
                    onTap: index < points.length - 1
                        ? () => setState(() => _selectedIndex = index)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selected.label}: ${formatBytes(selected.bytes)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  selected.previousBytes == null
                      ? 'Previous day unavailable'
                      : 'Previous day: ${formatBytes(selected.previousBytes!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: FlyxColors.mutedFor(context),
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.point,
    required this.maxBytes,
    required this.chartHeight,
    required this.selected,
    required this.interactive,
    required this.onTap,
  });

  final UsagePoint point;
  final double maxBytes;
  final double chartHeight;
  final bool selected;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = maxBytes <= 0 ? 0.0 : point.bytes / maxBytes;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                height: math.max(8, (chartHeight - 30) * fraction),
                decoration: BoxDecoration(
                  color: FlyxColors.accentFor(context).withValues(
                    alpha: selected ? 1 : .9,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 1.5,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            point.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : FlyxColors.mutedFor(context),
                  fontWeight: selected ? FontWeight.w700 : null,
                ),
          ),
        ],
      ),
    );

    if (!interactive) return content;

    return Semantics(
      button: true,
      label:
          '${point.label} data usage, ${formatBytes(point.bytes)}. Tap to show previous day usage.',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: FlyxColors.accentFor(context),
                size: 22,
              ),
              const SizedBox(height: 9),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
