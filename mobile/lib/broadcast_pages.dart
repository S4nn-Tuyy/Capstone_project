import 'dart:async';

import 'package:flutter/material.dart';

import 'm0_repository.dart';
import 'broadcast_repository.dart';

class BroadcastPage extends StatefulWidget {
  const BroadcastPage({
    super.key,
    required this.profile,
    required this.gateway,
    required this.onSignOut,
  });

  final ResidentProfile profile;
  final BroadcastGateway gateway;
  final Future<void> Function() onSignOut;

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  late Future<List<BroadcastAnnouncement>> _received;
  late Future<List<BroadcastAnnouncement>> _sent;
  StreamSubscription<void>? _changes;

  bool get _canPublish =>
      const ['pengurus_rt', 'pengurus_rw', 'admin'].contains(widget.profile.role);

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.gateway.watchChanges(widget.profile.id).listen((_) => _refresh());
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.gateway.dispose();
    super.dispose();
  }

  void _load() {
    _received = widget.gateway.received(widget.profile.id);
    _sent = widget.gateway.sent(widget.profile.id);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_load);
  }

  Future<void> _openAnnouncement(
    BroadcastAnnouncement announcement, {
    required bool markRead,
  }) async {
    if (markRead && announcement.readAt == null) {
      try {
        await widget.gateway.markRead(announcement.id, widget.profile.id);
        _refresh();
      } catch (error) {
        if (mounted) _notice('Gagal mencatat pengumuman dibaca: $error');
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(announcement.title),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${_kindLabel(announcement.kind)} · ${_dateLabel(announcement.sentAt ?? announcement.createdAt)}'),
            const SizedBox(height: 16),
            SelectableText(announcement.content),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _compose() async {
    final result = await showDialog<BroadcastSubmission>(
      context: context,
      builder: (_) => BroadcastComposer(profile: widget.profile, gateway: widget.gateway),
    );
    if (result == null || !mounted) return;
    _refresh();
    _notice('Pengumuman terkirim ke ${result.recipientCount} akun.');
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Pengumuman'),
          actions: [
            IconButton(tooltip: 'Segarkan', onPressed: _refresh, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: 'Keluar', onPressed: widget.onSignOut, icon: const Icon(Icons.logout)),
          ],

        ),
        body: _canPublish
            ? DefaultTabController(
                length: 2,
                child: Column(children: [
                  const Material(
                    child: TabBar(tabs: [
                      Tab(text: 'Kotak masuk', icon: Icon(Icons.inbox_outlined)),
                      Tab(text: 'Terkirim', icon: Icon(Icons.send_outlined)),
                    ]),
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      _announcementList(_received, received: true),
                      _announcementList(_sent, received: false),
                    ]),
                  ),
                ]),
              )
            : _announcementList(_received, received: true),
        floatingActionButton: _canPublish
            ? FloatingActionButton.extended(
                key: const Key('broadcast_compose'),
                onPressed: _compose,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Buat pengumuman'),
              )
            : null,
      );

  Widget _announcementList(
    Future<List<BroadcastAnnouncement>> future, {
    required bool received,
  }) => FutureBuilder<List<BroadcastAnnouncement>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat pengumuman: ${snapshot.error}'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final announcements = snapshot.data!;
          if (announcements.isEmpty) {
            return Center(
              child: Text(received
                  ? 'Belum ada pengumuman untuk akun ini.'
                  : 'Belum ada pengumuman terkirim.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final announcement = announcements[index];
              final unread = received && announcement.readAt == null;
              return Card(
                child: ListTile(
                  key: Key('announcement_${announcement.id}'),
                  leading: CircleAvatar(
                    backgroundColor: announcement.kind == 'darurat'
                        ? Theme.of(context).colorScheme.errorContainer
                        : null,
                    child: Icon(announcement.kind == 'darurat'
                        ? Icons.warning_amber
                        : announcement.kind == 'penting'
                            ? Icons.priority_high
                            : Icons.campaign_outlined),
                  ),
                  title: Text(announcement.title,
                      style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null),
                  subtitle: Text(
                    '${_kindLabel(announcement.kind)} · ${_dateLabel(announcement.sentAt ?? announcement.createdAt)}\n${announcement.content}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: unread
                      ? const Icon(Icons.mark_email_unread_outlined)
                      : received
                          ? const Icon(Icons.drafts_outlined)
                          : const Icon(Icons.done_all),
                  onTap: () => _openAnnouncement(announcement, markRead: received),
                ),
              );
            },
          );
        },
      );

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String _kindLabel(String kind) => switch (kind) {
        'penting' => 'Penting',
        'darurat' => 'Darurat',
        _ => 'Umum',
      };
}

class BroadcastShortcut extends StatefulWidget {
  const BroadcastShortcut({
    super.key,
    required this.profileId,
    required this.gateway,
    required this.onPressed,
  });

  final String profileId;
  final BroadcastGateway gateway;
  final VoidCallback onPressed;

  @override
  State<BroadcastShortcut> createState() => _BroadcastShortcutState();
}

class _BroadcastShortcutState extends State<BroadcastShortcut> {
  late Future<int> _unreadCount;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.gateway.watchChanges(widget.profileId).listen((_) {
      if (mounted) setState(_load);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.gateway.dispose();
    super.dispose();
  }

  void _load() {
    _unreadCount = widget.gateway
        .received(widget.profileId)
        .then((items) => items.where((item) => item.readAt == null).length);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _unreadCount,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return IconButton(
            key: const Key('open_broadcast'),
            tooltip: 'Pengumuman${count > 0 ? ': $count belum dibaca' : ''}',
            onPressed: widget.onPressed,
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 99 ? '99+' : '$count'),
              child: const Icon(Icons.campaign_outlined),
            ),
          );
        },
      );
}

class BroadcastComposer extends StatefulWidget {
  const BroadcastComposer({super.key, required this.profile, required this.gateway});

  final ResidentProfile profile;
  final BroadcastGateway gateway;

  @override
  State<BroadcastComposer> createState() => _BroadcastComposerState();
}

class _BroadcastComposerState extends State<BroadcastComposer> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  late final Future<List<BroadcastRt>> _rts;
  String _kind = 'umum';
  String _audience = 'semua';
  String _targetRole = 'warga';
  String? _targetRtId;
  String? _error;
  bool _busy = false;

  bool get _isRt => widget.profile.role == 'pengurus_rt';

  @override
  void initState() {
    super.initState();
    _audience = _isRt ? 'rt' : 'semua';
    _rts = widget.gateway.availableRts();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? targetRtId;
      if (_audience == 'rt') {
        if (_isRt) {
          targetRtId = widget.profile.rtId;
        } else {
          final rts = await _rts;
          targetRtId = _targetRtId ?? (rts.isEmpty ? null : rts.first.id);
        }
        if (targetRtId == null) throw StateError('Pilih RT tujuan terlebih dahulu.');
      }
      final result = await widget.gateway.publish(
        kind: _kind,
        audience: _isRt ? 'rt' : _audience,
        targetRtId: targetRtId,
        targetRole: _audience == 'peran' ? _targetRole : null,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Buat pengumuman'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  key: const Key('broadcast_title'),
                  controller: _titleController,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Judul'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Judul wajib diisi'
                      : null,
                ),
                TextFormField(
                  key: const Key('broadcast_content'),
                  controller: _contentController,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 5000,
                  decoration: const InputDecoration(labelText: 'Isi pengumuman'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Isi wajib diisi'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  key: const Key('broadcast_kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: const [
                    DropdownMenuItem(value: 'umum', child: Text('Umum')),
                    DropdownMenuItem(value: 'penting', child: Text('Penting')),
                    DropdownMenuItem(value: 'darurat', child: Text('Darurat')),
                  ],
                  onChanged: _busy ? null : (value) => setState(() => _kind = value ?? 'umum'),
                ),
                if (_isRt)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_work_outlined),
                    title: const Text('Audiens: RT Anda'),
                    subtitle: const Text('Pengurus RT hanya dapat mengirim ke RT sendiri.'),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: const Key('broadcast_audience'),
                    initialValue: _audience,
                    decoration: const InputDecoration(labelText: 'Penerima'),
                    items: const [
                      DropdownMenuItem(value: 'semua', child: Text('Semua akun terverifikasi')),
                      DropdownMenuItem(value: 'rt', child: Text('Satu RT')),
                      DropdownMenuItem(value: 'peran', child: Text('Berdasarkan peran')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _audience = value ?? 'semua'),
                  ),
                  if (_audience == 'rt') _targetRtField(),
                  if (_audience == 'peran') _targetRoleField(),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            key: const Key('broadcast_send'),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Kirim sekarang'),
          ),
        ],
      );

  Widget _targetRtField() => FutureBuilder<List<BroadcastRt>>(
        future: _rts,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Gagal memuat daftar RT: ${snapshot.error}');
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final rts = snapshot.data!;
          if (rts.isEmpty) return const Text('Tidak ada RT yang dapat dipilih.');
          final selected = rts.any((rt) => rt.id == _targetRtId)
              ? _targetRtId
              : rts.first.id;
          return DropdownButtonFormField<String>(
            key: const Key('broadcast_target_rt'),
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'RT tujuan'),
            items: [
              for (final rt in rts)
                DropdownMenuItem(value: rt.id, child: Text('${rt.code} · ${rt.name}')),
            ],
            onChanged: _busy ? null : (value) => setState(() => _targetRtId = value),
          );
        },
      );

  Widget _targetRoleField() => DropdownButtonFormField<String>(
        key: const Key('broadcast_target_role'),
        initialValue: _targetRole,
        decoration: const InputDecoration(labelText: 'Peran penerima'),
        items: const [
          DropdownMenuItem(value: 'warga', child: Text('Warga')),
          DropdownMenuItem(value: 'security', child: Text('Security')),
          DropdownMenuItem(value: 'pengurus_rt', child: Text('Pengurus RT')),
          DropdownMenuItem(value: 'pengurus_rw', child: Text('Pengurus RW')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
        ],
        onChanged: _busy ? null : (value) => setState(() => _targetRole = value ?? 'warga'),
      );
}
