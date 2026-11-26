import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'broadcast_pages.dart';
import 'broadcast_repository.dart';
import 'm0_pages.dart';
import 'm0_repository.dart';
import 'm1_pages.dart';
import 'm1_repository.dart';
import 'resident_pages.dart';
import 'resident_repository.dart';
import 'resident_home.dart';
import 'ticket_management_pages.dart';
import 'ticket_management_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || publishableKey.isEmpty) {
    runApp(MaterialApp(
      theme: WesbarTheme.light,
      home: Scaffold(
        body: Center(
            child: Text('Konfigurasi Supabase belum disediakan. '
                'Lihat mobile/README.md.')),
      ),
    ));
    return;
  }
  await Supabase.initialize(url: url, publishableKey: publishableKey);
  runApp(WesbarApp(repository: M0Repository(Supabase.instance.client)));
}

class WesbarApp extends StatefulWidget {
  const WesbarApp({super.key, required this.repository});

  final M0Repository repository;

  @override
  State<WesbarApp> createState() => _WesbarAppState();
}

class _WesbarAppState extends State<WesbarApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  ResidentProfile? _profile;
  bool _signedIn = false;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _authSubscription = widget.repository.authChanges.listen((_) => _reload());
    // Avoid setState during the first build; restored sessions are read here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final signedIn = widget.repository.signedInUser != null;
      final profile = signedIn ? await widget.repository.getMyProfile() : null;
      if (!mounted || generation != _generation) return;
      setState(() {
        _signedIn = signedIn;
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _signedIn = widget.repository.signedInUser != null;
        _error = 'Gagal memuat profil: $error';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await widget.repository.signOut();
    await _reload();
  }

  void _openBroadcast(ResidentProfile profile) {
    _navigatorKey.currentState?.push<void>(MaterialPageRoute<void>(
      builder: (_) => BroadcastPage(
        profile: profile,
        gateway: SupabaseBroadcastGateway(widget.repository.client),
        onSignOut: _signOut,
      ),
    ));
  }

  void _openResidentManagement(ResidentProfile profile) {
    _navigatorKey.currentState?.push<void>(MaterialPageRoute<void>(
      builder: (_) => ResidentManagementPage(
        profile: profile,
        gateway: SupabaseResidentManagementGateway(widget.repository.client),
      ),
    ));
  }

  void _openTicketManagement(ResidentProfile profile) {
    _navigatorKey.currentState?.push<void>(MaterialPageRoute<void>(
      builder: (_) => TicketManagementPage(
        profile: profile,
        gateway: SupabaseTicketManagementGateway(widget.repository.client),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Wesbar',
      theme: WesbarTheme.light,
      home: _buildPage(),
    );
  }

  Widget _buildPage() {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: _reload, child: const Text('Coba lagi')),
            if (_signedIn)
              TextButton(onPressed: _signOut, child: const Text('Keluar')),
          ]),
        ),
      );
    }
    if (!_signedIn) {
      return AuthPage(
        onSignIn: widget.repository.signIn,
        onSignUp: widget.repository.signUp,
        onSessionChanged: _reload,
      );
    }
    final profile = _profile;
    if (profile == null) {
      return OnboardingPage(
        onSubmit: ({
          required name,
          required phone,
          required rtCode,
          required jalanName,
          required houseNumber,
          required consent,
        }) async {
          await widget.repository.registerResident(
            name: name,
            phone: phone,
            rtCode: rtCode,
            jalanName: jalanName,
            houseNumber: houseNumber,
            consent: consent,
          );
          await _reload();
        },
        onSignOut: _signOut,
      );
    }
    if (!profile.isVerified) {
      return VerificationStatusPage(
        profile: profile,
        onRefresh: _reload,
        onSignOut: _signOut,
      );
    }
    if (profile.role == 'warga') {
      return ResidentHomeShell(
        profile: profile,
        repository: widget.repository,
        onSignOut: _signOut,
      );
    }
    final panicGateway = SupabasePanicGateway(widget.repository.client);
    final broadcastGateway = SupabaseBroadcastGateway(widget.repository.client);
    if (profile.role == 'pengurus_rt' && profile.rtId != null) {
      return RtVerificationPage(
        profile: profile,
        loadPending: widget.repository.pendingResidents,
        verify: (profileId, rtId, approve) => widget.repository.verifyResident(
          profileId: profileId,
          rtId: rtId,
          approve: approve,
        ),
        panicGateway: panicGateway,
        broadcastGateway: broadcastGateway,
        onOpenBroadcast: () => _openBroadcast(profile),
        onOpenIncidents: () {
          _navigatorKey.currentState?.push<void>(MaterialPageRoute<void>(
            builder: (_) => IncidentInboxPage(
              profile: profile,
              gateway: SupabasePanicGateway(widget.repository.client),
              broadcastGateway:
                  SupabaseBroadcastGateway(widget.repository.client),
              onSignOut: _signOut,
              onOpenBroadcast: () => _openBroadcast(profile),
              onManageTickets: () => _openTicketManagement(profile),
            ),
          ));
        },
        onManageResidents: () => _openResidentManagement(profile),
        onManageTickets: () => _openTicketManagement(profile),
        onSignOut: _signOut,
      );
    }
    if (const ['security', 'pengurus_rw', 'admin'].contains(profile.role)) {
      return IncidentInboxPage(
        profile: profile,
        gateway: panicGateway,
        broadcastGateway: broadcastGateway,
        onSignOut: _signOut,
        onOpenBroadcast: () => _openBroadcast(profile),
        onManageResidents: profile.role == 'admin'
            ? () => _openResidentManagement(profile)
            : null,
        onManageTickets: const ['pengurus_rw', 'admin'].contains(profile.role)
            ? () => _openTicketManagement(profile)
            : null,
      );
    }
    return VerifiedHomePage(profile: profile, onSignOut: _signOut);
  }
}
