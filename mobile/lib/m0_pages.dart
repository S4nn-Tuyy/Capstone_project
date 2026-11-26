import 'dart:async';

import 'package:flutter/material.dart';

import 'broadcast_pages.dart';
import 'broadcast_repository.dart';
import 'm0_repository.dart';
import 'm1_repository.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onSessionChanged,
  });

  final Future<void> Function(String email, String password) onSignIn;
  // Returns true when the user must confirm email before logging in.
  final Future<bool> Function(String email, String password) onSignUp;
  final Future<void> Function() onSessionChanged;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _signUpConsent = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    if (_signUp && !_signUpConsent) {
      setState(() => _message = 'Setujui penggunaan email untuk membuat akun.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signUp) {
        final confirmationNeeded = await widget.onSignUp(
          _email.text.trim(),
          _password.text,
        );
        if (confirmationNeeded) {
          if (mounted) {
            setState(() => _message =
                'Periksa email untuk konfirmasi, lalu masuk kembali.');
          }
        } else {
          await widget.onSessionChanged();
        }
      } else {
        await widget.onSignIn(_email.text.trim(), _password.text);
        await widget.onSessionChanged();
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Gagal masuk/daftar: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wesbar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(_signUp ? 'Daftar akun warga' : 'Masuk',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) => value == null ||
                          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())
                      ? 'Masukkan email yang valid'
                      : null,
                ),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Kata sandi'),
                  obscureText: true,
                  validator: (value) => value == null || value.length < 6
                      ? 'Minimal 6 karakter'
                      : null,
                ),
                if (_signUp)
                  CheckboxListTile(
                    key: const Key('signup_consent'),
                    contentPadding: EdgeInsets.zero,
                    value: _signUpConsent,
                    onChanged: _busy
                        ? null
                        : (value) =>
                            setState(() => _signUpConsent = value ?? false),
                    title: const Text('Saya setuju email saya digunakan untuk '
                        'membuat akun dan menghubungi saya terkait verifikasi.'),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_signUp ? 'Daftar' : 'Masuk'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signUp = !_signUp;
                            _signUpConsent = false;
                            _message = null;
                          }),
                  child: Text(
                      _signUp ? 'Sudah punya akun? Masuk' : 'Daftar warga'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, key: const Key('auth_message')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onSubmit,
    required this.onSignOut,
  });

  final Future<void> Function({
    required String name,
    required String phone,
    required String rtCode,
    required String jalanName,
    required String houseNumber,
    required bool consent,
  }) onSubmit;
  final Future<void> Function() onSignOut;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _rt = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _rt, _street, _number]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    if (!_consent) {
      setState(() => _error = 'Persetujuan penggunaan data wajib diberikan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        rtCode: _rt.text.trim(),
        jalanName: _street.text.trim(),
        houseNumber: _number.text.trim(),
        consent: _consent,
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Pendaftaran gagal: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data warga (M0)'),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: _busy ? null : widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('Alamat harus sudah didata pengurus. Pengurus RT '
                    'akan memeriksa identitas dan rumah sebelum akun aktif.'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama lengkap'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                      labelText: 'Nomor telepon (opsional)'),
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: _rt,
                  decoration:
                      const InputDecoration(labelText: 'Kode RT, contoh 01'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _street,
                  decoration: const InputDecoration(
                      labelText: 'Nama jalan sesuai data pengurus'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _number,
                  decoration: const InputDecoration(labelText: 'Nomor rumah'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('consent_checkbox'),
                  contentPadding: EdgeInsets.zero,
                  value: _consent,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _consent = value ?? false),
                  title: const Text(
                      'Saya setuju data nama, kontak, dan alamat rumah '
                      'dipakai untuk verifikasi dan layanan warga.'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Ajukan verifikasi'),
                ),
                if (_error != null)
                  Text(_error!, key: const Key('onboarding_error')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi' : null;
}

class VerificationStatusPage extends StatelessWidget {
  const VerificationStatusPage({
    super.key,
    required this.profile,
    required this.onRefresh,
    required this.onSignOut,
  });

  final ResidentProfile profile;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final rejected = profile.verificationStatus == 'ditolak';
    return Scaffold(
      appBar: AppBar(title: const Text('Status verifikasi')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rejected
                ? 'Pendaftaran ditolak. Hubungi pengurus RT untuk koreksi data.'
                : 'Menunggu verifikasi dari pengurus RT.'),
            TextButton(
                onPressed: onRefresh, child: const Text('Perbarui status')),
            TextButton(onPressed: onSignOut, child: const Text('Keluar')),
          ],
        ),
      ),
    );
  }
}

class VerifiedHomePage extends StatelessWidget {
  const VerifiedHomePage(
      {super.key, required this.profile, required this.onSignOut});

  final ResidentProfile profile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wesbar - M0')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Halo, ${profile.name}'),
            Text('Peran: ${profile.role}'),
            if (profile.address != null) Text('Alamat: ${profile.address}'),
            const Text(
                'Akun terverifikasi. Fitur aplikasi akan tampil sesuai peran akun.'),
            TextButton(onPressed: onSignOut, child: const Text('Keluar')),
          ]),
        ),
      );
}

class RtVerificationPage extends StatefulWidget {
  const RtVerificationPage({
    super.key,
    required this.profile,
    required this.loadPending,
    required this.verify,
    required this.panicGateway,
    required this.onSignOut,
    this.broadcastGateway,
    this.onOpenIncidents,
    this.onOpenBroadcast,
    this.onManageResidents,
    this.onManageTickets,
  });

  final ResidentProfile profile;
  final Future<List<ResidentProfile>> Function(String rtId) loadPending;
  final Future<void> Function(String profileId, String rtId, bool approve)
      verify;
  final PanicGateway panicGateway;
  final Future<void> Function() onSignOut;
  final BroadcastGateway? broadcastGateway;
  final VoidCallback? onOpenIncidents;
  final VoidCallback? onOpenBroadcast;
  final VoidCallback? onManageResidents;
  final VoidCallback? onManageTickets;

  @override
  State<RtVerificationPage> createState() => _RtVerificationPageState();
}

class _RtVerificationPageState extends State<RtVerificationPage> {
  late Future<List<ResidentProfile>> _pending;
  late Future<List<IncidentSummary>> _activeIncidents;
  StreamSubscription<void>? _incidentChanges;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pending = widget.loadPending(widget.profile.rtId!);
    _activeIncidents = widget.panicGateway.activeIncidents();
    _incidentChanges = widget.panicGateway
        .watchChanges(widget.profile.id)
        .listen((_) => _refresh());
  }

  @override
  void dispose() {
    _incidentChanges?.cancel();
    widget.panicGateway.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _pending = widget.loadPending(widget.profile.rtId!);
      _activeIncidents = widget.panicGateway.activeIncidents();
    });
  }

  Future<void> _verify(ResidentProfile person, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Setujui warga?' : 'Tolak pendaftaran?'),
        content:
            Text('Pastikan identitas dan alamat ${person.name} sudah dicek.'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.verify(person.id, widget.profile.rtId!, approve);
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
          title: const Text('Verifikasi warga RT'),
          actions: [
            if (widget.onManageResidents != null)
              IconButton(
                key: const Key('manage_residents'),
                tooltip: 'Kelola data warga',
                onPressed: widget.onManageResidents,
                icon: const Icon(Icons.people_alt_outlined),
              ),
            if (widget.onOpenIncidents != null)
              FutureBuilder<List<IncidentSummary>>(
                future: _activeIncidents,
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return IconButton(
                    key: const Key('rt_incident_inbox_button'),
                    tooltip:
                        'Insiden darurat${count > 0 ? ': $count aktif' : ''}',
                    onPressed: widget.onOpenIncidents,
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.sos),
                    ),
                  );
                },
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
                onPressed: _busy ? null : widget.onSignOut,
                icon: const Icon(Icons.logout)),
          ],
        ),
        body: Column(children: [
          if (widget.onOpenIncidents != null)
            FutureBuilder<List<IncidentSummary>>(
              future: _activeIncidents,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    margin: const EdgeInsets.all(12),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: const Text('Gagal memeriksa insiden aktif'),
                      subtitle: Text('${snapshot.error}'),
                      trailing: IconButton(
                        tooltip: 'Coba lagi',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  );
                }
                final count = snapshot.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Card(
                  key: const Key('rt_active_incidents_banner'),
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(Icons.sos,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    title: Text('$count insiden aktif perlu diperhatikan'),
                    subtitle:
                        const Text('Ketuk untuk membuka kotak masuk insiden.'),
                    onTap: widget.onOpenIncidents,
                  ),
                );
              },
            ),
          if (widget.onManageTickets != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('manage_tickets'),
                  onPressed: widget.onManageTickets,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('Kelola tiket layanan'),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<ResidentProfile>>(
              future: _pending,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Gagal memuat: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final people = snapshot.data!;
                if (people.isEmpty) {
                  return const Center(
                    child: Text('Tidak ada warga menunggu verifikasi.'),
                  );
                }
                return ListView.builder(
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return ListTile(
                      title: Text(person.name),
                      subtitle: Text(
                          'Alamat: ${person.address ?? "tidak tersedia"} - '
                          'cocokkan identitas dan penghuni secara langsung'),
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(
                            tooltip: 'Tolak ${person.name}',
                            icon: const Icon(Icons.close),
                            onPressed:
                                _busy ? null : () => _verify(person, false)),
                        IconButton(
                            tooltip: 'Setujui ${person.name}',
                            icon: const Icon(Icons.check),
                            onPressed:
                                _busy ? null : () => _verify(person, true)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );
}
