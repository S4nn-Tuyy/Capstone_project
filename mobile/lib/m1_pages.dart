import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'broadcast_pages.dart';
import 'broadcast_repository.dart';
import 'm0_repository.dart';
import 'm1_repository.dart';
import 'panic_layout.dart';
import 'status_indicator.dart';

class PanicButtonPage extends StatefulWidget {
  const PanicButtonPage({
    super.key,
    required this.profile,
    required this.gateway,
  });

  final ResidentProfile profile;
  final PanicGateway gateway;

  @override
  State<PanicButtonPage> createState() => _PanicButtonPageState();
}

class _PanicButtonPageState extends State<PanicButtonPage>
    with WidgetsBindingObserver {
  late Future<List<EmergencyContact>> _contacts;
  late Future<List<IncidentSummary>> _incidents;
  late Future<List<IncidentSummary>> _incomingIncidents;
  StreamSubscription<void>? _changes;
  Timer? _countdown;
  Timer? _retryTimer;
  int _secondsLeft = 0;
  bool _training = false;
  bool _sending = false;
  String _kind = 'keamanan';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _changes = widget.gateway.watchChanges(widget.profile.id).listen((_) {
      if (mounted) _load();
    });
    _retryTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _retryQueue());
    _retryQueue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdown?.cancel();
    _retryTimer?.cancel();
    _changes?.cancel();
    widget.gateway.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retryQueue();
  }

  void _load() {
    _contacts = widget.gateway.contacts(widget.profile.rtId!);
    _incidents = widget.gateway.myActiveIncidents(widget.profile.id);
    _incomingIncidents = widget.gateway.incomingIncidents(widget.profile.id);
    if (mounted) setState(() {});
  }

  Future<void> _retryQueue() async {
    try {
      final delivered = await widget.gateway.retryPending();
      if (delivered > 0 && mounted) {
        _load();
        _notice('$delivered alert tertunda berhasil dikirim ke server.');
      }
    } catch (_) {
      // The queued event stays on-device and is retried later.
    }
  }

  void _startCountdown() {
    if (_sending || _countdown != null) return;
    setState(() => _secondsLeft = 3);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        _countdown = null;
        setState(() => _secondsLeft = 0);
        _sendAlert();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _cancelCountdown() {
    _countdown?.cancel();
    _countdown = null;
    setState(() => _secondsLeft = 0);
  }

  Future<void> _sendAlert() async {
    if (_training) {
      _notice(
          'Mode latihan: alert tidak disimpan dan tidak dikirim ke penerima.');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.gateway.send(_kind);
      _notice(result.message ??
          (result.queued
              ? 'Alert menunggu koneksi dan akan dicoba ulang.'
              : 'Alert terkirim.'));
      _load();
    } catch (error) {
      _notice('Alert tidak terkirim: $error. Gunakan kontak darurat di bawah.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _respond(IncidentSummary incident, String response) async {
    setState(() => _sending = true);
    try {
      await widget.gateway.respond(incident.id, response);
      _notice('Respons alert berhasil dikirim.');
      _load();
    } catch (error) {
      _notice('Gagal mengirim respons: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _responseLabel(String? response) => switch (response) {
        'menuju' => 'Saya menuju lokasi',
        'tidak_bisa' => 'Tidak bisa membantu',
        _ => 'Menunggu respons',
      };

  Future<void> _call(EmergencyContact contact) async {
    final uri = Uri(scheme: 'tel', path: contact.phone);
    try {
      if (!await launchUrl(uri)) {
        throw StateError('Perangkat tidak mendukung panggilan langsung.');
      }
    } catch (_) {
      if (mounted) _notice('Hubungi ${contact.name}: ${contact.phone}');
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Darurat')),
        body: PanicLayout(
          name: widget.profile.name,
          address: widget.profile.address ?? 'Alamat belum tersedia',
          types: const [
            PanicType('keamanan', 'Keamanan', Icons.shield_outlined),
            PanicType(
                'kebakaran', 'Kebakaran', Icons.local_fire_department_outlined),
            PanicType('medis', 'Medis', Icons.medical_services_outlined),
            PanicType('lainnya', 'Lainnya', Icons.help_outline),
          ],
          selectedType: _kind,
          onTypeChanged: _secondsLeft > 0 || _sending
              ? null
              : (value) => setState(() => _kind = value),
          practiceMode: _training,
          onPracticeChanged: _secondsLeft > 0 || _sending
              ? null
              : (value) => setState(() => _training = value),
          onSos: _sending ? null : _startCountdown,
          countdownSeconds: _secondsLeft,
          onCancelCountdown: _cancelCountdown,
          sending: _sending,
          activeIncidents: _activeIncidents(),
          incomingAlerts: _incomingAlerts(),
          contacts: _emergencyContacts(),
        ),
      );

  Widget _activeIncidents() => FutureBuilder<List<IncidentSummary>>(
        future: _incidents,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyNote('Insiden belum dapat dimuat: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyNote('Tidak ada insiden aktif.');
          }
          return Column(
            children: [
              for (final incident in snapshot.data!)
                _IncidentCard(
                  incident: incident,
                  gateway: widget.gateway,
                  showResponses: true,
                ),
            ],
          );
        },
      );

  Widget _incomingAlerts() => FutureBuilder<List<IncidentSummary>>(
        future: _incomingIncidents,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyNote(
                'Alert masuk belum dapat dimuat: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyNote('Tidak ada alert masuk yang aktif.');
          }
          return Column(
            children: [
              for (final incident in snapshot.data!)
                _IncidentCard(
                  incident: incident,
                  gateway: widget.gateway,
                  showResponses: false,
                  actions: incident.recipientResponse == 'menunggu'
                      ? [
                          OutlinedButton.icon(
                            key: Key('respond_${incident.id}_menuju'),
                            onPressed: _sending
                                ? null
                                : () => _respond(incident, 'menuju'),
                            icon: const Icon(Icons.directions_run),
                            label: const Text('Saya menuju'),
                          ),
                          OutlinedButton(
                            key: Key('respond_${incident.id}_tidak_bisa'),
                            onPressed: _sending
                                ? null
                                : () => _respond(incident, 'tidak_bisa'),
                            child: const Text('Tidak bisa'),
                          ),
                        ]
                      : [
                          Text(
                            'Respons Anda: '
                            '${_responseLabel(incident.recipientResponse)}',
                          ),
                        ],
                ),
            ],
          );
        },
      );

  Widget _emergencyContacts() => FutureBuilder<List<EmergencyContact>>(
        future: _contacts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyNote(
                'Kontak darurat belum dapat dimuat: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyNote(
              'Kontak belum disiapkan pengurus. Jika darurat, '
              'hubungi layanan resmi setempat.',
            );
          }
          return Column(
            children: [
              for (final contact in snapshot.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call),
                  title: Text(contact.name),
                  subtitle:
                      Text('${contact.type ?? 'Umum'} - ${contact.phone}'),
                  onTap: () => _call(contact),
                ),
            ],
          );
        },
      );
}

class IncidentInboxPage extends StatefulWidget {
  const IncidentInboxPage({
    super.key,
    required this.profile,
    required this.gateway,
    required this.onSignOut,
    this.broadcastGateway,
    this.onOpenBroadcast,
    this.onManageResidents,
    this.onManageTickets,
  });

  final ResidentProfile profile;
  final PanicGateway gateway;
  final Future<void> Function() onSignOut;
  final BroadcastGateway? broadcastGateway;
  final VoidCallback? onOpenBroadcast;
  final VoidCallback? onManageResidents;
  final VoidCallback? onManageTickets;

  @override
  State<IncidentInboxPage> createState() => _IncidentInboxPageState();
}

class _IncidentInboxPageState extends State<IncidentInboxPage> {
  late Future<List<IncidentSummary>> _incidents;
  StreamSubscription<void>? _changes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _incidents = widget.gateway.activeIncidents();
    _changes = widget.gateway
        .watchChanges(widget.profile.id)
        .listen((_) => _refresh());
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.gateway.dispose();
    super.dispose();
  }

  void _refresh() =>
      setState(() => _incidents = widget.gateway.activeIncidents());

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Insiden darurat'),
          actions: [
            if (widget.onManageResidents != null)
              IconButton(
                key: const Key('manage_residents'),
                tooltip: 'Kelola data warga',
                onPressed: widget.onManageResidents,
                icon: const Icon(Icons.people_alt_outlined),
              ),
            if (widget.onOpenBroadcast != null &&
                widget.broadcastGateway != null)
              BroadcastShortcut(
                profileId: widget.profile.id,
                gateway: widget.broadcastGateway!,
                onPressed: widget.onOpenBroadcast!,
              )
            else if (widget.onOpenBroadcast != null)
              IconButton(
                key: const Key('open_broadcast'),
                tooltip: 'Pengumuman',
                onPressed: widget.onOpenBroadcast,
                icon: const Icon(Icons.campaign_outlined),
              ),
            IconButton(
                tooltip: 'Segarkan',
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh)),
            IconButton(
                tooltip: 'Keluar',
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout)),
          ],
        ),
        body: Column(
          children: [
            if (widget.onManageTickets != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('manage_tickets'),
                    onPressed: widget.onManageTickets,
                    icon: const Icon(Icons.confirmation_number_outlined),
                    label: const Text('Kelola tiket wilayah'),
                  ),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<IncidentSummary>>(
                future: _incidents,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Gagal memuat insiden: ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final incidents = snapshot.data!;
                  if (incidents.isEmpty) {
                    return const Center(
                        child: Text('Tidak ada insiden aktif.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: incidents.length,
                    itemBuilder: (context, index) {
                      final incident = incidents[index];
                      return _IncidentCard(
                        incident: incident,
                        gateway: widget.gateway,
                        showResponses: false,
                        actions: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _act(() => widget.gateway
                                    .respond(incident.id, 'menuju')),
                            icon: const Icon(Icons.directions_run),
                            label: const Text('Saya menuju'),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _act(() => widget.gateway
                                    .respond(incident.id, 'tidak_bisa')),
                            child: const Text('Tidak bisa'),
                          ),
                          if (incident.status == 'aktif')
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => widget.gateway
                                      .updateStatus(incident.id, 'ditangani')),
                              child: const Text('Tandai ditangani'),
                            ),
                          if (incident.status == 'ditangani') ...[
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => widget.gateway
                                      .updateStatus(incident.id, 'selesai')),
                              child: const Text('Selesai'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _confirmFalseAlarm(incident),
                              child: const Text('Alarm palsu'),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );

  Future<void> _confirmFalseAlarm(IncidentSummary incident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tandai alarm palsu?'),
        content: const Text('Gunakan hanya setelah insiden diperiksa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Konfirmasi')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _act(() => widget.gateway.updateStatus(incident.id, 'alarm_palsu'));
    }
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.gateway,
    required this.showResponses,
    this.actions = const [],
  });

  final IncidentSummary incident;
  final PanicGateway gateway;
  final bool showResponses;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _label(incident.kind),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                StatusIndicator.incident(context, incident.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(incident.location),
            Text('Dibuat: ${incident.createdAt.toLocal()}'),
            if (incident.escalatedAt != null) ...[
              const SizedBox(height: 8),
              StatusIndicator.escalation(context),
              const SizedBox(height: 4),
              const Text(
                'Belum ada penerima yang menuju lokasi dalam 60 detik.',
              ),
            ],
            if (showResponses)
              FutureBuilder<int>(
                future: gateway.responders(incident.id),
                builder: (context, snapshot) => Text(
                  snapshot.hasData
                      ? '${snapshot.data} penerima menyatakan menuju lokasi.'
                      : 'Memuat respons penerima…',
                ),
              ),
            if (actions.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 4, children: actions),
          ]),
        ),
      );

  String _label(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
