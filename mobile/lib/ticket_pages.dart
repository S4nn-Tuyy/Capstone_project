import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'm0_repository.dart';
import 'status_indicator.dart';
import 'ticket_repository.dart';

class ResidentTicketsPage extends StatefulWidget {
  const ResidentTicketsPage({
    super.key,
    required this.profile,
    required this.gateway,
    this.pickImage,
  });

  final ResidentProfile profile;
  final TicketGateway gateway;
  final Future<XFile?> Function()? pickImage;

  @override
  State<ResidentTicketsPage> createState() => _ResidentTicketsPageState();
}

class _ResidentTicketsPageState extends State<ResidentTicketsPage> {
  late Future<List<ResidentTicket>> _tickets;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _tickets = widget.gateway.myTickets(widget.profile.id);
  }

  void _reload() {
    setState(() => _tickets = widget.gateway.myTickets(widget.profile.id));
  }

  Future<void> _compose() async {
    final draft = await showDialog<_TicketDraft>(
      context: context,
      builder: (_) => _TicketComposer(
        pickImage: widget.pickImage,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _creating = true);
    try {
      await widget.gateway.createTicket(
        profile: widget.profile,
        category: draft.category,
        description: draft.description,
        photo: draft.photo,
      );
      if (!mounted) return;
      setState(() => _tickets = widget.gateway.myTickets(widget.profile.id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content: Text('Tiket berhasil dibuat dengan status Baru.')),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Tiket gagal dibuat: $error')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showDetails(ResidentTicket ticket) => showDialog<void>(
        context: context,
        builder: (_) => _TicketDetailsDialog(
          ticket: ticket,
          gateway: widget.gateway,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Tiket saya'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang tiket',
              onPressed: _creating ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: FutureBuilder<List<ResidentTicket>>(
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
                          Text('${snapshot.error}',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _reload,
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

                final tickets = snapshot.data!;
                if (tickets.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_outlined, size: 48),
                          SizedBox(height: 12),
                          Text('Belum ada tiket.'),
                          SizedBox(height: 4),
                          Text('Buat tiket untuk melaporkan kebutuhan warga.'),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    return Card(
                      child: ListTile(
                        key: Key('ticket_${ticket.id}'),
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondaryContainer,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          child: Icon(_categoryIcon(ticket.category)),
                        ),
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(_categoryLabel(ticket.category)),
                            StatusIndicator.ticket(context, ticket.status),
                          ],
                        ),
                        subtitle: Text(
                          '${ticket.description}\n${ticket.address}\n${_dateLabel(ticket.createdAt)}'
                          '${ticket.photoPath == null ? '' : ' · Foto terlampir'}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetails(ticket),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('ticket_create'),
          onPressed: _creating ? null : _compose,
          icon: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.add),
          label: Text(_creating ? 'Mengirim tiket…' : 'Buat tiket'),
        ),
      );

  String _categoryLabel(String category) =>
      TicketCategories.labels[category] ?? category;

  IconData _categoryIcon(String category) => switch (category) {
        'fasilitas' => Icons.home_repair_service_outlined,
        'keamanan' => Icons.shield_outlined,
        'hewan' => Icons.pets_outlined,
        'listrik' => Icons.bolt_outlined,
        _ => Icons.assignment_outlined,
      };

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }
}

class _TicketDraft {
  const _TicketDraft({
    required this.category,
    required this.description,
    this.photo,
  });

  final String category;
  final String description;
  final XFile? photo;
}

class _TicketComposer extends StatefulWidget {
  const _TicketComposer({this.pickImage});

  final Future<XFile?> Function()? pickImage;

  @override
  State<_TicketComposer> createState() => _TicketComposerState();
}

class _TicketComposerState extends State<_TicketComposer> {
  static const _maxPhotoBytes = 5 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _category = 'fasilitas';
  XFile? _photo;
  int? _photoSize;
  bool _picking = false;
  String? _photoError;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    try {
      final picker = widget.pickImage;
      final photo = picker != null
          ? await picker()
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 80,
            );
      if (photo == null) return;

      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty || bytes.length > _maxPhotoBytes) {
        setState(() => _photoError = 'Ukuran foto maksimal 5 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _photoSize = bytes.length;
        _photoError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _photoError = 'Foto tidak dapat dipilih: $error');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _TicketDraft(
        category: _category,
        description: _descriptionController.text.trim(),
        photo: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Buat tiket'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tiket akan mencatat alamat rumah dan waktu pengajuan.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('ticket_category'),
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      for (final entry in TicketCategories.labels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _category = value ?? 'fasilitas'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('ticket_description'),
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Jelaskan kebutuhan atau masalah',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Deskripsi wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('ticket_add_photo'),
                    onPressed: _picking ? null : _pickPhoto,
                    icon: _picking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                        _picking ? 'Membuka foto…' : 'Tambah foto (opsional)'),
                  ),
                  if (_photo != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: Text(_photo!.name),
                        subtitle:
                            Text('${((_photoSize ?? 0) / 1024).ceil()} KB'),
                        trailing: IconButton(
                          key: const Key('ticket_remove_photo'),
                          tooltip: 'Hapus foto',
                          onPressed: () => setState(() {
                            _photo = null;
                            _photoSize = null;
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  ],
                  if (_photoError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _photoError!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('ticket_submit'),
            onPressed: _picking ? null : _submit,
            child: const Text('Kirim tiket'),
          ),
        ],
      );
}

class _TicketDetailsDialog extends StatelessWidget {
  const _TicketDetailsDialog({required this.ticket, required this.gateway});

  final ResidentTicket ticket;
  final TicketGateway gateway;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(TicketCategories.labels[ticket.category] ?? ticket.category),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusIndicator.ticket(context, ticket.status),
                const SizedBox(height: 4),
                Text(ticket.address),
                const SizedBox(height: 4),
                Text(_dateLabel(ticket.createdAt)),
                const SizedBox(height: 12),
                Text(ticket.description),
                if (ticket.photoPath != null) ...[
                  const SizedBox(height: 16),
                  FutureBuilder<String>(
                    future: gateway.signedPhotoUrl(ticket.photoPath!),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text('Foto tiket tidak dapat dimuat.');
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text('Foto tiket tidak dapat ditampilkan.'),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      );

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }
}
