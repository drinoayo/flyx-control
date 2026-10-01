import 'dart:math' as math;

import 'package:flutter/material.dart';

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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: FlyxColors.muted),
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
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFF171B20) : FlyxColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: emphasized ? const Color(0xFF303640) : FlyxColors.line,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 28,
            spreadRadius: -20,
            offset: Offset(0, 12),
            color: Colors.black54,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: (online ? FlyxColors.success : FlyxColors.muted).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: (online ? FlyxColors.success : FlyxColors.muted).withValues(alpha: .18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: online ? FlyxColors.success : FlyxColors.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label ?? (online ? 'Online' : 'Offline'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: online ? FlyxColors.success : FlyxColors.muted,
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
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: FlyxColors.muted)),
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
    final foreground = blocked ? FlyxColors.danger : FlyxColors.yellow;
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
        painter: _SparkPainter(values),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);
  final List<double> values;

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
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x44FFCB05), Color(0x00FFCB05)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final paint = Paint()
      ..color = FlyxColors.yellow
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => oldDelegate.values != values;
}

class UsageBars extends StatelessWidget {
  const UsageBars({super.key, required this.points, this.height = 142});
  final List<UsagePoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Usage history will appear here as it is collected.')),
      );
    }
    final maxBytes = points.map((p) => p.bytes).reduce(math.max).toDouble();
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((point) {
          final fraction = maxBytes <= 0 ? 0.0 : point.bytes / maxBytes;
          return Expanded(
            child: Padding(
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
                        height: math.max(8, (height - 30) * fraction),
                        decoration: BoxDecoration(
                          color: FlyxColors.yellow.withValues(alpha: .9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    point.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: FlyxColors.muted),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
            color: FlyxColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FlyxColors.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: FlyxColors.yellow, size: 22),
              const SizedBox(height: 9),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
