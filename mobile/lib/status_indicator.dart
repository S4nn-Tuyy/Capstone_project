import 'package:flutter/material.dart';

import 'app_theme.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static StatusIndicator ticket(BuildContext context, String status) {
    final colors =
        Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    return switch (status) {
      'baru' => StatusIndicator(
          label: 'Baru',
          icon: Icons.schedule_outlined,
          color: colors.pending,
        ),
      'ditugaskan' => StatusIndicator(
          label: 'Ditugaskan',
          icon: Icons.assignment_ind_outlined,
          color: colors.progress,
        ),
      'diproses' => StatusIndicator(
          label: 'Diproses',
          icon: Icons.sync_outlined,
          color: colors.progress,
        ),
      'selesai' => StatusIndicator(
          label: 'Selesai',
          icon: Icons.check_circle_outline,
          color: colors.done,
        ),
      'ditutup' => StatusIndicator(
          label: 'Ditutup',
          icon: Icons.task_alt,
          color: colors.done,
        ),
      _ => StatusIndicator(
          label: _humanize(status),
          icon: Icons.info_outline,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    };
  }

  static StatusIndicator incident(BuildContext context, String status) {
    final colors =
        Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    return switch (status) {
      'aktif' => StatusIndicator(
          label: 'Aktif',
          icon: Icons.warning_amber_rounded,
          color: colors.escalated,
        ),
      'ditangani' => StatusIndicator(
          label: 'Ditangani',
          icon: Icons.handyman_outlined,
          color: colors.progress,
        ),
      'selesai' => StatusIndicator(
          label: 'Selesai',
          icon: Icons.check_circle_outline,
          color: colors.done,
        ),
      'alarm_palsu' => StatusIndicator(
          label: 'Alarm palsu',
          icon: Icons.report_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      _ => StatusIndicator(
          label: _humanize(status),
          icon: Icons.info_outline,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    };
  }

  static StatusIndicator escalation(BuildContext context) {
    final colors =
        Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    return StatusIndicator(
      label: 'Eskalasi',
      icon: Icons.notification_important_outlined,
      color: colors.escalated,
    );
  }

  static String _humanize(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
