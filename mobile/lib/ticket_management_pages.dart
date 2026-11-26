import 'package:flutter/material.dart';

import 'm0_repository.dart';
import 'panic_layout.dart';
import 'status_indicator.dart';
import 'ticket_management_repository.dart';
import 'ticket_repository.dart';

class TicketManagementPage extends StatefulWidget {
  const TicketManagementPage({
    super.key,
    required this.profile,
    required this.gateway,
  });

  final ResidentProfile profile;
  final TicketManagementGateway gateway;

  @override
  State<TicketManagementPage> createState() => _TicketManagementPageState();
}

class _TicketManagementPageState extends State<TicketManagementPage> {
  static const _filters = [
    'semua',
    'baru',
    'ditugaskan',
    'diproses',
    'selesai',
    'ditutup',
  ];

  late Future<List<ManagedTicket>> _tickets;
  String _filter = 'semua';

  @override
  void initState() {
    super.initState();
    _tickets = widget.gateway.tickets(widget.profile);
  }

  void _refresh() {
    setState(() {
      _tickets = widget.gateway.tickets(widget.profile);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Tiket wilayah'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang tiket',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      for (final status in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(status)),
                            selected: status == _filter,
                            onSelected: (_) => setState(() => _filter = status),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<ManagedTicket>>(
                    future: _tickets,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 40),
                                const SizedBox(height: 12),
                                const Text('Tiket belum dapat dimuat.'),
                                const SizedBox(height: 8),
                                Text(
                                  '${snapshot.error}',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _refresh,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Coba lagi'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final tickets = snapshot.data!
                          .where((ticket) =>
                              _filter == 'semua' || ticket.status == _filter)
                          .toList();
                      if (tickets.isEmpty) {
                        return Center(
                          child: EmptyNote(
                            _filter == 'semua'
                                ? 'Belum ada tiket di wilayah ini.'
                                : 'Tidak ada tiket berstatus ${_filterLabel(_filter)}.',
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: tickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final ticket = tickets[index];
                          return Card(
                            child: ListTile(
                              key: Key('managed_ticket_${ticket.id}'),
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                                child: Icon(_categoryIcon(ticket.category)),
                              ),
                              title: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(_categoryLabel(ticket.category)),
                                  StatusIndicator.ticket(
                                    context,
                                    ticket.status,
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${ticket.reporterName} · ${ticket.address}\n'
                                '${ticket.description}\n'
                                '${_dateLabel(ticket.createdAt)} · '
                                'Prioritas ${_humanize(ticket.priority)} · '
                                'Level ${ticket.level.toUpperCase()}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openTicket(ticket),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _openTicket(ManagedTicket ticket) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => TicketManagementDetailPage(
        profile: widget.profile,
        ticket: ticket,
        gateway: widget.gateway,
        onChanged: _refresh,
      ),
    ));
  }

  String _filterLabel(String status) => status == 'semua'
      ? 'Semua'
      : StatusIndicator.ticket(context, status).label;

  String _categoryLabel(String category) =>
      TicketCategories.labels[category] ?? _humanize(category);

  IconData _categoryIcon(String category) => switch (category) {
        'fasilitas' => Icons.home_repair_service_outlined,
        'keamanan' => Icons.shield_outlined,
        'hewan' => Icons.pets_outlined,
        'listrik' => Icons.bolt_outlined,
        _ => Icons.assignment_outlined,
      };

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _humanize(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class TicketManagementDetailPage extends StatefulWidget {
  const TicketManagementDetailPage({
    super.key,
    required this.profile,
    required this.ticket,
    required this.gateway,
    required this.onChanged,
  });

  final ResidentProfile profile;
  final ManagedTicket ticket;
  final TicketManagementGateway gateway;
  final VoidCallback onChanged;

  @override
  State<TicketManagementDetailPage> createState() =>
      _TicketManagementDetailPageState();
}

class _TicketManagementDetailPageState
    extends State<TicketManagementDetailPage> {
  late Future<List<TicketHistoryEvent>> _history;
  bool _saving = false;

  static const _statusTransitions = {
    'baru': 'ditugaskan',
    'ditugaskan': 'diproses',
    'diproses': 'selesai',
    'selesai': 'ditutup',
  };

  static const _actionLabels = {
    'ditugaskan': 'Tandai ditugaskan',
    'diproses': 'Mulai proses',
    'selesai': 'Tandai selesai',
    'ditutup': 'Tutup tiket',
  };

  @override
  void initState() {
    super.initState();
    _history = widget.gateway.history(widget.profile, widget.ticket.id);
  }

  bool get _canManage => switch (widget.profile.role) {
        'pengurus_rt' => widget.ticket.level == 'rt' &&
            widget.profile.rtId == widget.ticket.rtId,
        'pengurus_rw' || 'admin' => true,
        _ => false,
      };

  bool get _canEscalate =>
      widget.ticket.level == 'rt' &&
      !const ['selesai', 'ditutup'].contains(widget.ticket.status) &&
      (widget.profile.role == 'pengurus_rt' ||
          widget.profile.role == 'admin') &&
      _canManage;

  String? get _followingStatus => _statusTransitions[widget.ticket.status];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Detail tiket')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              TicketCategories.labels[widget.ticket.category] ??
                                  _humanize(widget.ticket.category),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            StatusIndicator.ticket(
                                context, widget.ticket.status),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _detailRow(
                          context,
                          Icons.person_outline,
                          widget.ticket.reporterName,
                        ),
                        _detailRow(
                          context,
                          Icons.location_on_outlined,
                          widget.ticket.address,
                        ),
                        _detailRow(
                          context,
                          Icons.flag_outlined,
                          'Prioritas ${_humanize(widget.ticket.priority)} · '
                          'Level ${widget.ticket.level.toUpperCase()}',
                        ),
                        _detailRow(
                          context,
                          Icons.schedule_outlined,
                          'Dibuat ${_dateLabel(widget.ticket.createdAt)}',
                        ),
                        const Divider(height: 24),
                        Text(
                          widget.ticket.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        _slaSummary(context),
                        if (widget.ticket.photoPath != null) ...[
                          const SizedBox(height: 16),
                          FutureBuilder<String>(
                            future: widget.gateway
                                .signedPhotoUrl(widget.ticket.photoPath!),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const EmptyNote(
                                  'Foto tiket tidak dapat dimuat.',
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  snapshot.data!,
                                  height: 320,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const EmptyNote(
                                    'Foto tiket tidak dapat ditampilkan.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _actions(context),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Riwayat tiket',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _historyList(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _actions(BuildContext context) {
    final nextStatus = _followingStatus;
    if (!_canManage || (nextStatus == null && !_canEscalate)) {
      if (widget.ticket.level == 'rw' && widget.profile.role == 'pengurus_rt') {
        return const EmptyNote(
          'Tiket telah dieskalasikan. Penanganan dilanjutkan pengurus RW.',
        );
      }
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (nextStatus != null)
          FilledButton.icon(
            key: Key('ticket_status_$nextStatus'),
            onPressed: _saving ? null : () => _updateStatus(nextStatus),
            icon: Icon(_statusActionIcon(nextStatus)),
            label: Text(_actionLabels[nextStatus]!),
          ),
        if (_canEscalate)
          OutlinedButton.icon(
            key: const Key('ticket_escalate'),
            onPressed: _saving ? null : _confirmEscalation,
            icon: const Icon(Icons.trending_up),
            label: const Text('Eskalasi ke RW'),
          ),
      ],
    );
  }

  Widget _historyList() => FutureBuilder<List<TicketHistoryEvent>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyNote('Riwayat tiket belum dapat dimuat.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyNote('Belum ada riwayat perubahan.');
          }
          return Column(
            children: [
              for (final event in snapshot.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_historyIcon(event.action)),
                  title: Text(_historyLabel(event)),
                  subtitle: Text(
                    '${_dateLabel(event.createdAt)}'
                    '${event.actorName == null ? '' : ' · ${event.actorName}'}',
                  ),
                ),
            ],
          );
        },
      );

  Widget _slaSummary(BuildContext context) {
    if (widget.ticket.responseDueAt == null &&
        widget.ticket.completionDueAt == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline),
        title: Text('Target SLA belum ditetapkan'),
      );
    }
    return Column(
      children: [
        if (widget.ticket.responseDueAt != null)
          _detailRow(
            context,
            Icons.timelapse,
            'Batas respons ${_dateLabel(widget.ticket.responseDueAt!)}',
          ),
        if (widget.ticket.completionDueAt != null)
          _detailRow(
            context,
            Icons.flag_outlined,
            'Batas penyelesaian ${_dateLabel(widget.ticket.completionDueAt!)}',
          ),
      ],
    );
  }

  Widget _detailRow(BuildContext context, IconData icon, String text) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Future<void> _updateStatus(String status) async {
    setState(() => _saving = true);
    try {
      await widget.gateway.updateStatus(
        profile: widget.profile,
        ticketId: widget.ticket.id,
        status: status,
      );
      widget.onChanged();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
            content: Text('Status tiket diperbarui: ${_humanize(status)}.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status tiket gagal diperbarui: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmEscalation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eskalasi tiket ke RW?'),
        content: const Text(
          'Pengurus RT tidak lagi dapat mengubah tiket setelah dieskalasikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eskalasi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.gateway.escalate(
        profile: widget.profile,
        ticketId: widget.ticket.id,
      );
      widget.onChanged();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Tiket dieskalasikan ke pengurus RW.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tiket gagal dieskalasikan: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  IconData _statusActionIcon(String status) => switch (status) {
        'ditugaskan' => Icons.assignment_ind_outlined,
        'diproses' => Icons.sync_outlined,
        'selesai' => Icons.check_circle_outline,
        'ditutup' => Icons.task_alt,
        _ => Icons.edit_outlined,
      };

  IconData _historyIcon(String action) => switch (action) {
        'dibuat' => Icons.add_circle_outline,
        'status' => Icons.sync_outlined,
        'eskalasi' => Icons.trending_up,
        _ => Icons.history,
      };

  String _historyLabel(TicketHistoryEvent event) => switch (event.action) {
        'dibuat' => 'Tiket dibuat',
        'status' => 'Status ${_humanize(event.statusBefore ?? 'baru')} → '
            '${_humanize(event.statusAfter ?? 'baru')}',
        'eskalasi' => 'Level ${event.levelBefore?.toUpperCase() ?? 'RT'} → '
            '${event.levelAfter?.toUpperCase() ?? 'RW'}',
        _ => _humanize(event.action),
      };

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _humanize(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
