import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_conversation.dart';
import '../../services/api_exceptions.dart';
import '../../services/chat_repository.dart';
import '../../theme/app_colors.dart';
import 'ai_settings_screen.dart';

/// Travel Buddy AI chat - ChatGPT-style.
///
/// - Hamburger -> Drawer with conversation list and "New Chat" button.
/// - Conversations + messages persist in the backend (per-user, SQLite).
/// - Conversation titles are auto-generated on the first message.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _conversationSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ChatConversation> _conversations = <ChatConversation>[];
  ChatConversation? _currentConversation;
  List<_LocalMessage> _messages = <_LocalMessage>[];

  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  bool _isAiTyping = false;
  int _aiRequestId = 0;
  int _messageLoadRequestId = 0;
  String? _loadError;

  static const String _welcomeText =
      "Hello! I'm your Travel Buddy AI. \nAsk me to suggest places, plan an itinerary, or about your own trips, expenses and reminders.";

  final List<String> _quickSuggestions = const [
    'Suggest a 3-day trip to Lahore',
    'Best time to visit Skardu?',
    'Top food spots in Karachi',
    'How much have I spent on food?',
  ];

  @override
  void initState() {
    super.initState();
    _conversationSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadConversations(autoSelectFirst: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _conversationSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatConversation> get _filteredConversations {
    final query = _conversationSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _conversations;
    return _conversations
        .where((c) =>
            c.title.toLowerCase().contains(query) ||
            (c.lastLocation ?? '').toLowerCase().contains(query))
        .toList(growable: true);
  }

  Future<void> _loadConversations({bool autoSelectFirst = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingConversations = true;
      _loadError = null;
    });
    try {
      final convs = await _repo.listConversations();
      if (!mounted) return;
      setState(() {
        // Wrap in a growable copy so we can later insert/remove safely.
        _conversations = List<ChatConversation>.from(convs);
        _isLoadingConversations = false;
      });
      if (autoSelectFirst && convs.isNotEmpty && _currentConversation == null) {
        await _openConversation(convs.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingConversations = false;
        _loadError = _humanise(e);
      });
    }
  }

  Future<void> _openConversation(ChatConversation conv) async {
    if (!mounted) return;
    final requestId = ++_messageLoadRequestId;
    setState(() {
      _currentConversation = conv;
      _isLoadingMessages = true;
      _messages = <_LocalMessage>[];
    });
    // Close the drawer via the Scaffold, not the Navigator: the drawer is part
    // of the Scaffold tree, not a pushed route, so Navigator.pop() would pop
    // the entire chat screen instead.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || requestId != _messageLoadRequestId) return;
    }
    try {
      final fetched = await _repo.getMessages(conv.id);
      if (!mounted || requestId != _messageLoadRequestId) return;
      setState(() {
        _messages = fetched
            .map((m) => _LocalMessage(
                  text: m.content,
                  isUser: m.isUser,
                  timestamp: m.createdAt,
                ))
            .where((m) => !_isOldFixedLengthError(m))
            .toList(growable: true);
        _isLoadingMessages = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted || requestId != _messageLoadRequestId) return;
      setState(() {
        _isLoadingMessages = false;
        _messages = <_LocalMessage>[
          _LocalMessage(
            text: 'Could not load this conversation: ${_humanise(e)}',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        ];
      });
    }
  }

  Future<void> _startNewChat() async {
    if (!mounted) return;
    _messageLoadRequestId++;
    setState(() {
      _currentConversation = null;
      _messages = <_LocalMessage>[];
      _isLoadingMessages = false;
    });
    // Same reason as _openConversation: close the drawer through the Scaffold
    // so we don't accidentally pop the chat screen.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
    }
    try {
      final conv = await _repo.createConversation();
      if (!mounted) return;
      setState(() {
        _currentConversation = conv;
        final updatedConversations = <ChatConversation>[
          conv,
          ..._conversations.where((c) => c.id != conv.id),
        ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _conversations = updatedConversations;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_assistantFailureMessage(e))),
      );
    }
  }

  Future<void> _deleteConversation(ChatConversation conv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text('"${conv.title}" and all of its messages will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteConversation(conv.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations.where((c) => c.id != conv.id).toList(growable: true);
        if (_currentConversation?.id == conv.id) {
          _currentConversation = null;
          _messages = <_LocalMessage>[];
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${_humanise(e)}')),
      );
    }
  }

  Future<void> _renameConversation(ChatConversation conv) async {
    // The dialog owns its own TextEditingController (via a StatefulWidget) so the
    // controller is disposed at exactly the right time — when the dialog leaves
    // the tree. Disposing it manually right after showDialog() returns (while the
    // dialog is still animating out) caused "TextEditingController used after
    // disposed" and a cascade of framework errors (_dependents.isEmpty / dirty
    // build scope / duplicate GlobalKeys / red screen).
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameChatDialog(initialTitle: conv.title),
    );
    final clean = title?.trim();
    if (clean == null || clean.isEmpty || clean == conv.title) return;

    try {
      final updated = await _repo.renameConversation(conv.id, clean);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .map((c) => c.id == updated.id ? updated : c)
            .toList(growable: true)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (_currentConversation?.id == updated.id) {
          _currentConversation = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename: ${_humanise(e)}')),
      );
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = (quickText ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;
    if (quickText == null) _messageController.clear();

    final now = DateTime.now();
    setState(() {
      _messages = <_LocalMessage>[
        ..._messages.where((m) => !m.isTransientError && !_isOldFixedLengthError(m)),
        _LocalMessage(text: text, isUser: true, timestamp: now),
      ];
      _isSending = true;
      _isAiTyping = true;
    });
    _scrollToBottom();

    final requestId = ++_aiRequestId;
    try {
      _currentConversation ??= await _repo.createConversation();
      final conv = _currentConversation!;
      final result = await _repo.sendMessage(conv.id, text);
      if (!mounted || requestId != _aiRequestId) return;
      setState(() {
        _messages = <_LocalMessage>[
          ..._messages,
          _LocalMessage(
            text: result.assistantMessage.content,
            isUser: false,
            timestamp: result.assistantMessage.createdAt,
          ),
        ];
        final updatedConversation = conv.copyWith(title: result.title, updatedAt: DateTime.now());
        _currentConversation = updatedConversation;
        final idx = _conversations.indexWhere((c) => c.id == conv.id);
        final updatedConversations = List<ChatConversation>.from(_conversations, growable: true);
        if (idx >= 0) {
          updatedConversations[idx] = updatedConversation;
        } else {
          updatedConversations.insert(0, updatedConversation);
        }
        updatedConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _conversations = updatedConversations;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted || requestId != _aiRequestId) return;
      setState(() {
        _messages = <_LocalMessage>[
          ..._messages,
          _LocalMessage(
            text: _assistantFailureMessage(e),
            isUser: false,
            timestamp: DateTime.now(),
            isTransientError: true,
          ),
        ];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isAiTyping = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  String _humanise(Object e) {
    if (e is ApiResponseException) return e.message;
    return e.toString();
  }

  String _assistantFailureMessage(Object e) {
    final msg = _humanise(e);
    if (e is NetworkException || msg.toLowerCase().contains('cannot reach backend')) {
      return "I can't connect to the Travel Buddy backend right now. Please check that the backend is running and try again.";
    }
    if (e is AuthException) {
      return "Your login session needs to be refreshed before I can continue this chat.";
    }
    if (e is ServerException || msg.toLowerCase().contains('api_key')) {
      return "Travel Buddy AI is temporarily unavailable. Please check the backend AI/API key setup and try again.";
    }
    return "I couldn't send that message. $msg";
  }

  bool _isOldFixedLengthError(_LocalMessage message) {
    return !message.isUser &&
        message.text.toLowerCase().contains('cannot add to a fixed-length list');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = cs.primary;
    final hasMessages = _messages.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      drawer: _buildDrawer(theme, isDark, primary),
      appBar: _buildAppBar(theme, isDark, primary),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMessages
                ? Center(child: CircularProgressIndicator(color: primary))
                : hasMessages
                    ? _buildMessageList(isDark, primary)
                    : _buildEmptyState(isDark, primary),
          ),
          if (!hasMessages && !_isLoadingMessages && !_isAiTyping)
            _buildQuickSuggestions(isDark, primary),
          _buildInputArea(isDark, primary),
        ],
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme, bool isDark, Color primary) {
    return Drawer(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withValues(alpha: 0.15),
                    child: Icon(Icons.travel_explore_rounded, color: primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Travel Buddy AI',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startNewChat,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Conversations',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: TextField(
                controller: _conversationSearchController,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  prefixIcon: Icon(Icons.search_rounded, size: 19, color: isDark ? Colors.white54 : Colors.black45),
                  suffixIcon: _conversationSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _conversationSearchController.clear,
                          tooltip: 'Clear search',
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceDarkElevated : AppColors.headerLilac,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoadingConversations
                  ? Center(child: CircularProgressIndicator(color: primary))
                  : _loadError != null
                      ? _buildSidebarError(isDark)
                      : _conversations.isEmpty
                          ? _buildEmptyDrawerHint(isDark)
                          : _filteredConversations.isEmpty
                              ? _buildNoSearchResults(isDark)
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: _filteredConversations.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                                  itemBuilder: (ctx, i) {
                                    final c = _filteredConversations[i];
                                    final active = _currentConversation?.id == c.id;
                                    return _ConversationTile(
                                      conversation: c,
                                      isActive: active,
                                      isDark: isDark,
                                      primary: primary,
                                      onTap: () => _openConversation(c),
                                      onRename: () => _renameConversation(c),
                                      onDelete: () => _deleteConversation(c),
                                    );
                                  },
                                ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.tune_rounded, color: isDark ? Colors.white70 : Colors.black54),
              title: Text(
                'AI Settings',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, AiSettingsScreen.routeName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarError(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 36, color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(height: 10),
          Text(
            _loadError ?? 'Failed to load conversations',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: () => _loadConversations(), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyDrawerHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 36, color: isDark ? Colors.white38 : Colors.black38),
          const SizedBox(height: 10),
          Text(
            'No chats yet.\nTap "New Chat" to begin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No matching chats',
          textAlign: TextAlign.center,
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark, Color primary) {
    final title = _currentConversation?.title ?? 'Travel Buddy AI';
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black87,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        tooltip: 'Chats',
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: primary.withValues(alpha: 0.15),
            child: Icon(Icons.smart_toy_rounded, color: primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  _isAiTyping ? 'Typing...' : 'Travel Buddy AI',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isAiTyping ? primary : (isDark ? Colors.white54 : Colors.black54),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_comment_outlined),
          tooltip: 'New Chat',
          onPressed: _startNewChat,
        ),
      ],
    );
  }

  Widget _buildMessageList(bool isDark, Color primary) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      reverse: true,
      itemCount: _messages.length + (_isAiTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isAiTyping && index == 0) return _TypingIndicator(primary: primary);
        final msg = _messages[_messages.length - 1 - (_isAiTyping ? index - 1 : index)];
        return _ChatBubble(message: msg, isDark: isDark, primary: primary);
      },
    );
  }

  Widget _buildEmptyState(bool isDark, Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: primary.withValues(alpha: 0.12),
              child: Icon(Icons.travel_explore_rounded, size: 38, color: primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Travel Buddy AI',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _welcomeText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSuggestions(bool isDark, Color primary) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickSuggestions.length,
        itemBuilder: (context, i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(_quickSuggestions[i]),
              labelStyle: TextStyle(
                color: isDark ? Colors.white : primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: isDark ? AppColors.surfaceDarkElevated : primary.withValues(alpha: 0.08),
              onPressed: _isSending ? null : () => _sendMessage(_quickSuggestions[i]),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea(bool isDark, Color primary) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDarkElevated : AppColors.headerLilac,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4,
                enabled: !_isSending,
                textInputAction: TextInputAction.send,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Ask about your trip...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSending ? null : () => _sendMessage(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isSending ? primary.withValues(alpha: 0.55) : primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Conversation tile (drawer row)
// ===========================================================================
class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final bool isActive;
  final bool isDark;
  final Color primary;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.isDark,
    required this.primary,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  String _relative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? (isDark ? primary.withValues(alpha: 0.20) : primary.withValues(alpha: 0.10))
        : Colors.transparent;
    final fg = isActive ? primary : (isDark ? Colors.white : Colors.black87);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 18, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: fg,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _relative(conversation.updatedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Chat options',
                  icon: Icon(Icons.more_vert_rounded, size: 18, color: isDark ? Colors.white54 : Colors.black54),
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Chat bubble
// ===========================================================================
class _ChatBubble extends StatelessWidget {
  final _LocalMessage message;
  final bool isDark;
  final Color primary;

  const _ChatBubble({required this.message, required this.isDark, required this.primary});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(
                            colors: [primary, primary.withGreen(180)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isUser ? null : (isDark ? AppColors.surfaceDarkElevated : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: SelectableText(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 8, right: isUser ? 8 : 0),
            child: Text(
              DateFormat('hh:mm a').format(message.timestamp),
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Typing indicator
// ===========================================================================
class _TypingIndicator extends StatelessWidget {
  final Color primary;
  const _TypingIndicator({required this.primary});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _AnimatedDot(delay: i * 150, color: primary)),
        ),
      ),
    );
  }
}

class _AnimatedDot extends StatefulWidget {
  final int delay;
  final Color color;
  const _AnimatedDot({required this.delay, required this.color});
  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.6), shape: BoxShape.circle),
      ),
    );
  }
}

// ===========================================================================
// Local message model (UI-only)
// ===========================================================================
class _LocalMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isTransientError;
  const _LocalMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isTransientError = false,
  });
}

// ===========================================================================
// Rename dialog — owns its own controller so the lifecycle is correct
// ===========================================================================
class _RenameChatDialog extends StatefulWidget {
  const _RenameChatDialog({required this.initialTitle});
  final String initialTitle;

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename chat'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Chat title',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
