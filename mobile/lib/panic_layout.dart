import 'package:flutter/material.dart';

import 'app_theme.dart';

class PanicType {
  const PanicType(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// Presentation-only layout; the owning page provides state and callbacks.
class PanicLayout extends StatelessWidget {
  const PanicLayout({
    super.key,
    required this.name,
    required this.address,
    required this.types,
    required this.selectedType,
    required this.onTypeChanged,
    required this.practiceMode,
    required this.onPracticeChanged,
    required this.onSos,
    required this.countdownSeconds,
    required this.onCancelCountdown,
    required this.sending,
    required this.activeIncidents,
    required this.incomingAlerts,
    required this.contacts,
  });

  final String name;
  final String address;
  final List<PanicType> types;
  final String selectedType;
  final ValueChanged<String>? onTypeChanged;
  final bool practiceMode;
  final ValueChanged<bool>? onPracticeChanged;
  final VoidCallback? onSos;
  final int countdownSeconds;
  final VoidCallback onCancelCountdown;
  final bool sending;
  final Widget activeIncidents;
  final Widget incomingAlerts;
  final Widget contacts;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Halo, $name', style: tt.headlineSmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                key: practiceMode ? const Key('training_mode_notice') : null,
                color: practiceMode ? cs.secondaryContainer : null,
                child: SwitchListTile(
                  value: practiceMode,
                  onChanged: onPracticeChanged,
                  title: Text(
                    'Mode latihan',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    practiceMode
                        ? 'Aktif. Tidak ada insiden atau penerima yang diberi tahu.'
                        : 'Coba tombol tanpa memberi tahu siapa pun.',
                  ),
                  secondary: Icon(
                    practiceMode ? Icons.school : Icons.school_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jenis keadaan darurat', style: tt.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in types)
                            ChoiceChip(
                              avatar: Icon(type.icon, size: 18),
                              label: Text(type.label),
                              selected: type.id == selectedType,
                              onSelected: onTypeChanged == null
                                  ? null
                                  : (_) => onTypeChanged!(type.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (countdownSeconds > 0) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            practiceMode
                                ? 'Latihan dimulai dalam $countdownSeconds detik'
                                : 'Alert dikirim dalam $countdownSeconds detik',
                            style: tt.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: OutlinedButton.icon(
                            key: const Key('cancel_panic_countdown'),
                            onPressed: onCancelCountdown,
                            icon: const Icon(Icons.close),
                            label: Text(
                              practiceMode
                                  ? 'Batalkan latihan'
                                  : 'Batalkan alert',
                            ),
                          ),
                        ),
                      ] else
                        Center(
                          child: _SosButton(
                            practice: practiceMode,
                            sending: sending,
                            onPressed: onSos,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          countdownSeconds > 0
                              ? 'Tekan batalkan jika tidak ingin mengirim alert.'
                              : 'Hitung mundur 3 detik, bisa dibatalkan.',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Insiden aktif saya',
                icon: Icons.report_outlined,
                child: activeIncidents,
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Alert untuk saya',
                icon: Icons.notifications_active_outlined,
                child: incomingAlerts,
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Kontak darurat',
                icon: Icons.call_outlined,
                child: contacts,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.practice,
    required this.sending,
    required this.onPressed,
  });

  final bool practice;
  final bool sending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final panicStyle = WesbarTheme.panicButton;
    final color =
        practice ? cs.primary : panicStyle.backgroundColor!.resolve(const {})!;
    final on = practice
        ? cs.onPrimary
        : panicStyle.foregroundColor!.resolve(const {})!;
    final panicShape = panicStyle.shape!.resolve(const {})!;

    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onPressed,
      label: practice
          ? 'Mulai latihan minta bantuan'
          : 'Minta bantuan darurat. Hitung mundur 3 detik.',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Material(
          color: color,
          shape: panicShape,
          child: InkWell(
            key: const Key('panic_button'),
            customBorder: panicShape,
            onTap: onPressed,
            child: SizedBox(
              width: 168,
              height: 168,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (sending)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(color: on),
                    )
                  else
                    Text(
                      'SOS',
                      style: TextStyle(
                        color: on,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    sending
                        ? 'MENGIRIM…'
                        : practice
                            ? 'LATIHAN'
                            : 'MINTA BANTUAN',
                    style: TextStyle(
                      color: on,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: tt.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Bottom navigation used by the verified resident area.
class WesbarNavBar extends StatelessWidget {
  const WesbarNavBar({
    super.key,
    required this.index,
    required this.onTap,
  });

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sos_outlined),
            selectedIcon: Icon(Icons.sos),
            label: 'Darurat',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Pengumuman',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Tiket',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      );
}
