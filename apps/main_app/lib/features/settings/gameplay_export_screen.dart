import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import 'gameplay_export_service.dart';
import 'widgets/settings_scaffold.dart';

class GameplayExportScreen extends StatefulWidget {
  const GameplayExportScreen({super.key, required this.palette});
  final GamePalette palette;

  @override
  State<GameplayExportScreen> createState() => _GameplayExportScreenState();
}

class _GameplayExportScreenState extends State<GameplayExportScreen> {
  bool _busy = false;

  Future<void> _export() async {
    final childId = context.read<ChildProvider>().activeChildId;
    if (childId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a child profile first.')),
      );
      return;
    }
    final verified = await ParentVerificationDialog.show(context);
    if (!verified || !mounted) return;
    setState(() => _busy = true);
    try {
      final files = await GameplayExportService().exportAndShare(childId: childId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export ready: ${files.length} files shared (CSV, JSON, and PDF).')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export gameplay: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Export Gameplay',
      icon: Icons.file_download_outlined,
      palette: widget.palette,
      children: [
        SettingsCard(children: [
          const Text('Share child gameplay data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('Exports a de-identified CSV and JSON data file plus a PDF summary for an authorized teacher, researcher, or your own records. The child\'s name and raw database ID are never included.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share_outlined),
            label: Text(_busy ? 'Preparing export...' : 'Export and share'),
          ),
        ]),
      ],
    );
  }
}
