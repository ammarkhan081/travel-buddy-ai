import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_conversation.dart';
import '../../models/chat_message.dart';
import '../../services/api_exceptions.dart';
import '../../services/chat_repository.dart';
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
    _loadConversations(autoSelectFirst: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
        _conversations = convs;
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
    setState(() {
      _currentConversation = conv;
      _isLoadingMessages = true;
      _messages = <_LocalMessage>[];
    });
    Navigator.of(context).maybePop();
    try {
      final fetched = await _repo.getMessages(conv.id);
      if (!mounted) return;
      setState(() {
        _messages = fetched
            .map((m) => _LocalMessage(
                  text: m.content,
                  isUser: m.isUser,
                  timestamp: m.createdAt,
                ))
            .toList();
        _isLoadingMessages = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
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
    setState(() {
      _currentConversation = null;
      _messages = <_LocalMessage>[];
    });
    Navigator.of(context).maybePop();
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
        _conversations.removeWhere((c) => c.id == conv.id);
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

  Future<void> _sendMessage([String? quickText]) async {
    final text = (quickText ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;
    if (quickText == null) _messageController.clear();

    final now = DateTime.now();
    setState(() {
      _messages.add(_LocalMessage(text: text, isUser: true, timestamp: now));
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
        _messages.add(_LocalMessage(
          text: result.assistantMessage.content,
          isUser: false,
          timestamp: result.assistantMessage.createdAt,
        ));
        _currentConversation = conv.copyWith(title: result.title, updatedAt: DateTime.now());
        final idx = _conversations.indexWhere((c) => c.id == conv.id);
        if (idx >= 0) {
          _conversations[idx] = _conversations[idx].copyWith(title: result.title, updatedAt: DateTime.now());
        } else {
          _conversations.insert(0, _currentConversation!);
        }
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted || requestId != _aiRequestId) return;
      setState(() {
        _messages.add(_LocalMessage(
          text: 'I encountered an error. ${_humanise(e)}',
          isUser: false,
          timestamp: DateTime.now(),
        ));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = cs.primary;
    final hasMessages = _messages.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? const Color(0xFF0E1320) : const Color(0xFFF6F7FB),
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
      backgroundColor: isDark ? const Color(0xFF131A2A) : Colors.white,
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
                    backgroundColor: primary.withOpacity(0.15),
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
            Expanded(
              child: _isLoadingConversations
                  ? Center(child: CircularProgressIndicator(color: primary))
                  : _loadError != null
                      ? _buildSidebarError(isDark)
                      : _conversations.isEmpty
                          ? _buildEmptyDrawerHint(isDark)
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _conversations.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 2),
                              itemBuilder: (ctx, i) {
                                final c = _conversations[i];
                                final active = _currentConversation?.id == c.id;
                                return _ConversationTile(
                                  conversation: c,
                                  isActive: active,
                                  isDark: isDark,
                                  primary: primary,
                                  onTap: () => _openConversation(c),
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

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark, Color primary) {
    final title = _currentConversation?.title ?? 'Travel Buddy AI';
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF131A2A) : Colors.white,
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
            backgroundColor: primary.withOpacity(0.15),
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
              backgroundColor: primary.withOpacity(0.12),
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
              backgroundColor: isDark ? const Color(0xFF1E293B) : primary.withOpacity(0.08),
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
        color: isDark ? const Color(0xFF131A2A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.05),
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
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
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
                color: _isSending ? primary.withOpacity(0.55) : primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.35),
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
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.isDark,
    required this.primary,
    required this.onTap,
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
        ? (isDark ? primary.withOpacity(0.20) : primary.withOpacity(0.10))
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
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: isDark ? Colors.white54 : Colors.black54,
                  onPressed: onDelete,
                  splashRadius: 18,
                  tooltip: 'Delete',
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
                    color: isUser ? null : (isDark ? const Color(0xFF1E293B) : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.18 : 0.04),
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
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
        decoration: BoxDecoration(color: widget.color.withOpacity(0.6), shape: BoxShape.circle),
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
  const _LocalMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
