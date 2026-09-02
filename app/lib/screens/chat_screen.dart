import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../api/orca_client.dart';
import '../theme.dart';
import '../widgets/agent_trace.dart';
import '../widgets/response_card.dart';
import 'map_screen.dart';

/// The main ORCA chat screen.
///
/// Layout (top to bottom):
///   * App bar with title + language chip
///   * Quick-prompt chips (one-tap examples)
///   * Streaming conversation
///       - user bubbles (right)
///       - assistant "thinking" card with streaming agent steps
///       - assistant final response with map + reasoning
///   * Input bar with text field + send button
class ChatScreen extends StatefulWidget {
  final OrcaClient client;
  const ChatScreen({super.key, required this.client});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  // The conversation: each entry is either a user message or a streaming
  // assistant response (in progress or completed).
  final List<_ChatEntry> _entries = [];

  // The current (in progress) assistant entry, if any.
  _AssistantEntry? _activeAssistant;

  // User's location. For the demo, default to Mumbai coast.
  LatLng? _userLocation = const LatLng(18.9, 72.8);

  String _language = 'en';

  static const _examples = [
    'Where is the nearest PFZ today?',
    'Is it safe to venture into the sea tomorrow morning?',
    'What is the safest route considering weather?',
    'Why has fish productivity declined?',
    'मछली कहाँ मिलेगी?',
    'மீன் எங்கே கிடைக்கும்?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    widget.client.close();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    final userEntry = _UserEntry(text: text);
    setState(() {
      _entries.add(userEntry);
      _activeAssistant = _AssistantEntry();
      _entries.add(_activeAssistant!);
      _input.clear();
    });
    _scrollToBottom();

    try {
      final stream = widget.client.askStreaming(
        text,
        location: _userLocation,
        language: _language,
      );
      await for (final ev in stream) {
        if (ev.isStep) {
          setState(() {
            _activeAssistant!.steps.add(ev.step!);
          });
        } else if (ev.isDone) {
          setState(() {
            _activeAssistant!.response = ev.done;
            _activeAssistant = null;
          });
        }
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _activeAssistant?.error = e.toString();
        _activeAssistant = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ORCA — Marine Intelligence'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Language',
            icon: Row(
              children: [
                const Icon(Icons.language, size: 18),
                const SizedBox(width: 4),
                Text(_language.toUpperCase(),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
              ],
            ),
            onSelected: (v) => setState(() => _language = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('हिन्दी (Hindi)')),
              PopupMenuItem(value: 'ta', child: Text('தமிழ் (Tamil)')),
            ],
          ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick-prompt chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.white,
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _examples
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(e, style: const TextStyle(fontSize: 12)),
                          onPressed: () => _send(e),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const Divider(height: 1),
          // Conversation
          Expanded(
            child: _entries.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => _buildEntry(_entries[i]),
                  ),
          ),
          // Input
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sailing, size: 64, color: OrcaColors.oceanBlue),
            const SizedBox(height: 16),
            const Text(
              'Ask ORCA about the sea',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Where can I fish today? Is it safe to go out? '
              'What\'s the weather? Try a quick prompt above or type below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: Text(
                'Using location: '
                '${_userLocation!.latitude.toStringAsFixed(2)}, '
                '${_userLocation!.longitude.toStringAsFixed(2)}',
              ),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: const InputDecoration(
                  hintText: 'Ask ORCA anything about the sea…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: () => _send(_input.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(_ChatEntry entry) {
    if (entry is _UserEntry) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: OrcaColors.oceanBlue,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            entry.text,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
      );
    } else if (entry is _AssistantEntry) {
      return _buildAssistantBubble(entry);
    }
    return const SizedBox.shrink();
  }

  Widget _buildAssistantBubble(_AssistantEntry e) {
    if (e.error != null) {
      return Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text('Could not reach the ORCA backend'),
          subtitle: Text('${e.error}\n\n'
              'Is the backend running on port 8000? '
              'If you\'re on a physical phone, change the URL in '
              'lib/api/orca_client.dart to your laptop\'s LAN IP.'),
        ),
      );
    }

    // Still streaming
    if (e.response == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Agents are thinking…',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: OrcaColors.oceanBlue)),
                ],
              ),
              const SizedBox(height: 10),
              AgentTraceList(steps: e.steps),
            ],
          ),
        ),
      );
    }

    // Completed response
    final r = e.response!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrcaResponseCard(response: r),
        if (r.hasMap)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SizedBox(
                  height: 220,
                  child: InlineMap(map: r.map, height: 220),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.map, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        '${r.map.polygons.length} zones, '
                        '${r.map.points.length} markers',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_full, size: 16),
                        label: const Text('Expand'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(map: r.map),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ORCA Marine Intelligence',
      applicationVersion: '0.1.0',
      applicationIcon: const Icon(Icons.sailing,
          color: OrcaColors.oceanBlue, size: 48),
      children: const [
        SizedBox(height: 8),
        Text(
          'ORCA is the SIH 2026 PS 176 solution — an Agentic AI platform '
          'for marine intelligence, built around a multi-agent pipeline '
          '(planner, weather, ocean, GIS, risk, reasoner).',
        ),
        SizedBox(height: 8),
        Text(
          'Every response shows the full reasoning trace so you can see '
          'why the answer is what it is.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Internal model classes for the chat list.

abstract class _ChatEntry {}

class _UserEntry extends _ChatEntry {
  final String text;
  _UserEntry({required this.text});
}

class _AssistantEntry extends _ChatEntry {
  final List<AgentStep> steps = [];
  OrcaResponse? response;
  String? error;
}
