import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'broadcast_pages.dart';
import 'broadcast_repository.dart';
import 'm0_repository.dart';
import 'm1_pages.dart';
import 'm1_repository.dart';
import 'panic_layout.dart';
import 'status_indicator.dart';
import 'ticket_pages.dart';
import 'ticket_repository.dart';

class ResidentHomeShell extends StatefulWidget {
  const ResidentHomeShell({
    super.key,
    required this.profile,
    required this.repository,
    required this.onSignOut,
  });

  final ResidentProfile profile;
  final M0Repository repository;
  final Future<void> Function() onSignOut;

  @override
  State<ResidentHomeShell> createState() => _ResidentHomeShellState();
}

class _ResidentHomeShellState extends State<ResidentHomeShell> {
  late final PanicGateway _panicGateway;
  late final BroadcastGateway _broadcastGateway;
  late final TicketGateway _ticketGateway;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final client = widget.repository.client;
    _panicGateway = SupabasePanicGateway(client);
    _broadcastGateway = SupabaseBroadcastGateway(client);
    _ticketGateway = SupabaseTicketGateway(client);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            PanicButtonPage(
              profile: widget.profile,
              gateway: _panicGateway,
            ),
            BroadcastPage(
              profile: widget.profile,
              gateway: _broadcastGateway,
              onSignOut: widget.onSignOut,
            ),
            ResidentTicketsPage(
              profile: widget.profile,
              gateway: _ticketGateway,
            ),
            _ResidentProfileTab(
              profile: widget.profile,
              onSignOut: widget.onSignOut,
            ),
          ],
        ),
        bottomNavigationBar: WesbarNavBar(
          index: _selectedIndex,
          onTap: (index) {
            if (index != _selectedIndex) {
              setState(() => _selectedIndex = index);
            }
          },
        ),
      );
}

class _ResidentProfileTab extends StatelessWidget {
  const _ResidentProfileTab({
    required this.profile,
    required this.onSignOut,
  });

  final ResidentProfile profile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        StatusIndicator(
                          label: 'Terverifikasi',
                          icon: Icons.verified_user_outlined,
                          color: StatusColors.light.done,
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.home_outlined),
                          title: const Text('Alamat'),
                          subtitle: Text(
                            profile.address ?? 'Alamat belum tersedia',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.groups_outlined),
                          title: const Text('Wilayah'),
                          subtitle: const Text('RW 5'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar dari akun'),
                ),
              ],
            ),
          ),
        ),
      );
}
