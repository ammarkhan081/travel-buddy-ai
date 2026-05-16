import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/fastapi_service.dart';
import '../../utils/ui_utils.dart';

class VoiceNotesModule extends StatefulWidget {
  const VoiceNotesModule({super.key});

  @override
  State<VoiceNotesModule> createState() => _VoiceNotesModuleState();
}

class _VoiceNotesModuleState extends State<VoiceNotesModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voice Notes')),
        body: const Center(child: Text('Please log in to view voice notes')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Notes'),
        backgroundColor: const Color(0xFF1E66F5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: FastApiService()
                  .get('/api/voice-notes/')
                  .then((res) => res as List<dynamic>),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final notes = snapshot.data ?? [];
                if (notes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic_none, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'No transcribed voice notes yet',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap the button below to record and transcribe',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final data = notes[index];
                    return _buildVoiceNoteCard(context, data);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.pushNamed(context, '/recordVoiceNote');
                if (!context.mounted) return;
                if (result == true) {
                  setState(() {});
                }
              },
              icon: const Icon(Icons.mic),
              label: const Text('Record & Transcribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E66F5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceNoteCard(BuildContext context, Map<String, dynamic> data) {
    final transcript = data['transcript'] ?? 'No text extracted';
    final timestampStr = data['timestamp'] ?? data['created_at'] ?? '';
    final date = DateTime.tryParse(timestampStr) ?? DateTime.now();
    final keywords = data['keywords'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.mic, color: Colors.purple),
        ),
        title: Text(
          transcript.length > 50 ? '${transcript.substring(0, 50)}...' : transcript,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy • hh:mm a').format(date)),
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Keywords: $keywords',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Note'),
                content: const Text('Permanently delete this transcribed note?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            );
            if (confirm == true) {
              try {
                await FastApiService().delete('/api/voice-notes/${data['id']}');
                if (!mounted) return;
                setState(() {});
              } catch (e) {
                if (!context.mounted) return;
                UIFeedback.showSnackBar(context, 'Error deleting: $e', isError: true);
              }
            }
          },
        ),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Full Transcript'),
              content: SingleChildScrollView(child: Text(transcript)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          );
        },
      ),
    );
  }
}

