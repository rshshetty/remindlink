
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:showcaseview/showcaseview.dart';
import 'core/database/database.dart';
import 'core/repositories/bookmark_repository.dart';
import 'core/repositories/reminder_repository.dart';
import 'core/platform/share_handler.dart';
import 'core/services/notification_service.dart';
import 'core/services/reminder_scheduler.dart';
import 'core/services/onboarding_service.dart';
import 'core/utils/url_parser.dart';

const kPrimary    = Color(0xFF1B3D2A);
const kPrimaryMid = Color(0xFF2D5A3F);
const kAccent     = Color(0xFF4CAF7D);
const kBg         = Color(0xFFF5F3EE);
const kGold       = Color(0xFFE8B84B);
const kTextSub    = Color(0xFF888888);

Color _platformColor(String platform) {
  switch (platform.toLowerCase()) {
    case 'instagram': return const Color(0xFFE1306C);
    case 'youtube':   return const Color(0xFFFF0000);
    case 'reddit':    return const Color(0xFFFF4500);
    case 'twitter':   return const Color(0xFF1DA1F2);
    case 'tiktok':    return const Color(0xFF010101);
    case 'linkedin':  return const Color(0xFF0077B5);
    case 'facebook':  return const Color(0xFF1877F2);
    case 'telegram':  return const Color(0xFF0088CC);
    default:          return kPrimary;
  }
}

IconData _platformIcon(String platform) {
  switch (platform.toLowerCase()) {
    case 'youtube':   return Icons.play_circle_fill;
    case 'reddit':    return Icons.forum;
    case 'twitter':   return Icons.tag;
    case 'tiktok':    return Icons.music_video;
    case 'linkedin':  return Icons.work;
    case 'facebook':  return Icons.facebook;
    case 'telegram':  return Icons.send;
    default:          return Icons.link;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await NotificationService.requestPermission();
  await ReminderScheduler.initialize();
  runApp(const RemindLinkApp());
}

class RemindLinkApp extends StatelessWidget {
  const RemindLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemindLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        scaffoldBackgroundColor: kBg,
        useMaterial3: true,
      ),
      home: ShowCaseWidget(
        builder: (context) => const BookmarkListScreen(),
      ),
    );
  }
}

class BookmarkListScreen extends StatefulWidget {
  const BookmarkListScreen({super.key});

  @override
  State<BookmarkListScreen> createState() => _BookmarkListScreenState();
}

class _BookmarkListScreenState extends State<BookmarkListScreen> {
  late final AppDatabase database;
  late final BookmarkRepository repository;
  late final ReminderRepository reminderRepository;

  List<Bookmark> bookmarks       = [];
  Map<int, Reminder> reminderMap = {};
  String selectedCategory        = 'All';
  bool isLoading                 = true;

  final _addKey    = GlobalKey();
  final _cardKey   = GlobalKey();
  final _alarmKey  = GlobalKey();
  final _deleteKey = GlobalKey();
  final _appBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    database           = AppDatabase();
    repository         = BookmarkRepository(database);
    reminderRepository = ReminderRepository(database);
    _initialize();
  }

Future<void> _initialize() async {
  await _handleIncomingShare();
  await _loadBookmarks();
  setState(() => isLoading = false);

  // Handle remind later action from notification
  NotificationService.onRemindLater = (reminderId, title, url) {
    if (mounted) {
      _showRemindLaterPicker(reminderId, title, url);
    }
  };

  // Check if app was launched via remind_later while closed
  final launchDetails = await NotificationService.getLaunchDetails();
  if (launchDetails?.notificationResponse?.actionId == 'remind_later' &&
      mounted) {
    final payload = launchDetails!.notificationResponse!.payload;
    if (payload != null) {
      final parts = payload.split('|');
      final remId = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
      final title = parts.length > 1 ? parts[1] : '';
      final url   = parts.length > 2 ? parts[2] : payload;
      _showRemindLaterPicker(remId, title, url);
    }
  }

  final isFirst = await OnboardingService.isFirstLaunch();
  if (isFirst && mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _startOnboarding());
  }
}

  void _startOnboarding() {
    ShowCaseWidget.of(context).startShowCase(
        [_appBarKey, _addKey, _cardKey, _alarmKey, _deleteKey]);
    OnboardingService.markComplete();
  }

  Future<void> _loadBookmarks() async {
    final loaded = await repository.getAllBookmarks();
    final Map<int, Reminder> reminders = {};
    for (final b in loaded) {
      final r = await reminderRepository.getReminderForBookmark(b.id);
      if (r != null) reminders[b.id] = r;
    }
    setState(() {
      bookmarks   = loaded;
      reminderMap = reminders;
    });
  }

  Future<void> _handleIncomingShare() async {
    final data = await ShareHandler.getSharedData();
    if (data == null || data['url'] == null) return;

    final url          = data['url']!;
    final titleCtrl    = TextEditingController();
    final categoryCtrl = TextEditingController(
      text: UrlParser.detectPlatform(url),
    );
    DateTime remindAt = DateTime.now()
        .add(const Duration(days: 1))
        .copyWith(hour: 9, minute: 0, second: 0, millisecond: 0);

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, ss) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Save & Remind',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(url,
                      style: const TextStyle(
                          fontSize: 11, color: kTextSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 12),
                _GreenTextField(
                    controller: titleCtrl,
                    label: 'Title',
                    hint: 'e.g. Interesting recipe'),
                const SizedBox(height: 12),
                _GreenTextField(
                    controller: categoryCtrl,
                    label: 'Category',
                    hint: 'e.g. Instagram'),
                const SizedBox(height: 16),
                const Text('REMIND ME AT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kTextSub,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                _DateTimePickerWidget(
                  initialDateTime: remindAt,
                  onChanged: (dt) => ss(() => remindAt = dt),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await repository.saveBookmark(
                  url: url,
                  title: titleCtrl.text.trim().isEmpty
                      ? null
                      : titleCtrl.text.trim(),
                  platform: categoryCtrl.text.trim().isEmpty
                      ? null
                      : categoryCtrl.text.trim(),
                );
                await _loadBookmarks();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save only',
                  style: TextStyle(color: kPrimary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (remindAt.isBefore(DateTime.now())) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please select a future time')),
                  );
                  return;
                }
                final bookmarkId = await repository.saveBookmark(
                  url: url,
                  title: titleCtrl.text.trim().isEmpty
                      ? null
                      : titleCtrl.text.trim(),
                  platform: categoryCtrl.text.trim().isEmpty
                      ? null
                      : categoryCtrl.text.trim(),
                );
                await reminderRepository.createReminderWithNotification(
                  bookmarkId: bookmarkId,
                  remindAt: remindAt,
                  bookmarkTitle: titleCtrl.text.trim().isEmpty
                      ? url
                      : titleCtrl.text.trim(),
                  bookmarkUrl: url,
                );
                await _loadBookmarks();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save & Remind',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],

          
        ),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved with reminder!')),
      );
    }

    // Return to previous app after snackbar shows
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      SystemNavigator.pop();
    }
  }

  Future<void> _showBookmarkSheet({String? url}) async {
    final urlCtrl      = TextEditingController(text: url ?? '');
    final titleCtrl    = TextEditingController();
    final categoryCtrl = TextEditingController(
      text: url != null ? UrlParser.detectPlatform(url) : '',
    );
    DateTime remindAt = DateTime.now()
        .add(const Duration(days: 1))
        .copyWith(hour: 9, minute: 0, second: 0, millisecond: 0);

    urlCtrl.addListener(() {
      final u = urlCtrl.text.trim();
      if (u.isNotEmpty) {
        categoryCtrl.text = UrlParser.detectPlatform(u);
      }
    });

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _BottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 8),
                Text(
                  url != null ? 'Save & Remind' : 'Add Bookmark',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kPrimary),
                ),
                const SizedBox(height: 20),
                if (url != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(url,
                        style: const TextStyle(
                            fontSize: 12, color: kTextSub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  )
                else
                  _GreenTextField(
                      controller: urlCtrl,
                      label: 'Paste URL',
                      hint: 'https://...'),
                const SizedBox(height: 12),
                _GreenTextField(
                    controller: titleCtrl,
                    label: 'Title',
                    hint: 'e.g. Interesting recipe'),
                const SizedBox(height: 12),
                _GreenTextField(
                    controller: categoryCtrl,
                    label: 'Category',
                    hint: 'e.g. Instagram'),
                const SizedBox(height: 20),
                const Text('REMIND ME AT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kTextSub,
                        letterSpacing: 1.2)),
                const SizedBox(height: 12),
                _DateTimePickerWidget(
                  initialDateTime: remindAt,
                  onChanged: (dt) => ss(() => remindAt = dt),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final u = urlCtrl.text.trim().isEmpty
                              ? url ?? ''
                              : urlCtrl.text.trim();
                          if (u.isEmpty) return;
                          await repository.saveBookmark(
                            url: u,
                            title: titleCtrl.text.trim().isEmpty
                                ? null
                                : titleCtrl.text.trim(),
                            platform: categoryCtrl.text.trim().isEmpty
                                ? null
                                : categoryCtrl.text.trim(),
                          );
                          await _loadBookmarks();
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kPrimary,
                          side: const BorderSide(color: kPrimary),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save only'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final u = urlCtrl.text.trim().isEmpty
                              ? url ?? ''
                              : urlCtrl.text.trim();
                          if (u.isEmpty) return;
                          if (remindAt.isBefore(DateTime.now())) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Please select a future time')));
                            return;
                          }
                          final id = await repository.saveBookmark(
                            url: u,
                            title: titleCtrl.text.trim().isEmpty
                                ? null
                                : titleCtrl.text.trim(),
                            platform: categoryCtrl.text.trim().isEmpty
                                ? null
                                : categoryCtrl.text.trim(),
                          );
                          await reminderRepository
                              .createReminderWithNotification(
                            bookmarkId: id,
                            remindAt: remindAt,
                            bookmarkTitle:
                                titleCtrl.text.trim().isEmpty
                                    ? u
                                    : titleCtrl.text.trim(),
                            bookmarkUrl: u,
                          );
                          await _loadBookmarks();
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Saved with reminder!')));
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save & Remind',
                            style: TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditSheet(Bookmark bookmark) async {
    final titleCtrl    = TextEditingController(text: bookmark.title);
    final categoryCtrl = TextEditingController(text: bookmark.platform);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _BottomSheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 8),
              const Text('Edit Bookmark',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kPrimary)),
              const SizedBox(height: 6),
              Text(bookmark.url,
                  style: const TextStyle(
                      fontSize: 12, color: kTextSub),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              _GreenTextField(
                  controller: titleCtrl,
                  label: 'Title',
                  hint: ''),
              const SizedBox(height: 12),
              _GreenTextField(
                  controller: categoryCtrl,
                  label: 'Category',
                  hint: ''),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await repository.updateBookmark(
                      id: bookmark.id,
                      title: titleCtrl.text.trim().isEmpty
                          ? bookmark.title
                          : titleCtrl.text.trim(),
                      platform: categoryCtrl.text.trim().isEmpty
                          ? bookmark.platform
                          : categoryCtrl.text.trim(),
                    );
                    await _loadBookmarks();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Updated!')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Changes',
                      style:
                          TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReminderSheet(Bookmark bookmark) async {
    final existing =
        await reminderRepository.getReminderForBookmark(bookmark.id);
    final titleCtrl = TextEditingController(text: bookmark.title);
    DateTime remindAt = existing?.remindAt ??
        DateTime.now()
            .add(const Duration(days: 1))
            .copyWith(hour: 9, minute: 0, second: 0, millisecond: 0);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _BottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 8),
                Text(
                  existing == null
                      ? 'Set Reminder'
                      : 'Edit Reminder',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kPrimary),
                ),
                const SizedBox(height: 20),
                _GreenTextField(
                    controller: titleCtrl,
                    label: 'Title',
                    hint: ''),
                const SizedBox(height: 20),
                const Text('REMIND ME AT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kTextSub,
                        letterSpacing: 1.2)),
                const SizedBox(height: 12),
                _DateTimePickerWidget(
                  initialDateTime: remindAt,
                  onChanged: (dt) => ss(() => remindAt = dt),
                ),
                const SizedBox(height: 24),
                if (existing != null)
                  TextButton.icon(
                    onPressed: () async {
                      await reminderRepository
                          .deleteReminderWithNotification(
                              existing.id);
                      await _loadBookmarks();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Reminder deleted')));
                      }
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    label: const Text('Delete reminder',
                        style: TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (remindAt.isBefore(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please select a future time')));
                        return;
                      }
                      if (existing != null) {
                        await reminderRepository
                            .deleteReminderWithNotification(
                                existing.id);
                      }
                      await reminderRepository
                          .createReminderWithNotification(
                        bookmarkId: bookmark.id,
                        remindAt: remindAt,
                        bookmarkTitle:
                            titleCtrl.text.trim().isEmpty
                                ? bookmark.title
                                : titleCtrl.text.trim(),
                        bookmarkUrl: bookmark.url,
                      );
                      await _loadBookmarks();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                                content: Text(existing == null
                                    ? 'Reminder set!'
                                    : 'Reminder updated!')));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      existing == null
                          ? 'Set Reminder'
                          : 'Update Reminder',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
    await _loadBookmarks();
  }

Future<void> _showRemindLaterPicker(
    int reminderId, String title, String url) async {
  DateTime remindAt = DateTime.now()
      .add(const Duration(hours: 1))
      .copyWith(second: 0, millisecond: 0);

  if (!mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, ss) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Remind Later',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: kPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              const Text('REMIND ME AT',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kTextSub,
                      letterSpacing: 1.2)),
              const SizedBox(height: 10),
              _DateTimePickerWidget(
                initialDateTime: remindAt,
                onChanged: (dt) => ss(() => remindAt = dt),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Future.delayed(const Duration(milliseconds: 400));
              if (mounted) SystemNavigator.pop();
            },
            child: const Text('Cancel',
                style: TextStyle(color: kTextSub)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (remindAt.isBefore(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please select a future time')),
                );
                return;
              }
              await NotificationService.scheduleNotification(
                id: reminderId,
                title: title,
                body: 'Tap to open your bookmark',
                scheduledTime: remindAt,
                payload: '$reminderId|$title|$url',
              );
              await reminderRepository.updateReminderTime(
                reminderId: reminderId,
                newRemindAt: remindAt,
              );
              await _loadBookmarks();
              if (context.mounted) Navigator.pop(context);
              await Future.delayed(const Duration(milliseconds: 400));
              if (mounted) SystemNavigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Set Reminder',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

  @override
  void dispose() {
    database.close();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(
            child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    final categories = [
      'All',
      ...bookmarks.map((b) => b.platform).toSet()
    ];
    final filtered = selectedCategory == 'All'
        ? bookmarks
        : bookmarks
            .where((b) => b.platform == selectedCategory)
            .toList();

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: kPrimary,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.only(left: 20, bottom: 14),
              title: Showcase(
                key: _appBarKey,
                title: 'Welcome to RemindLink!',
                description:
                    'Save links from anywhere and get reminded at the right time.',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RemindLink',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    Text(
                      '${bookmarks.length} bookmark${bookmarks.length == 1 ? '' : 's'} saved',
                      style: TextStyle(
                          color:
                              Colors.white.withValues(alpha: 0.65),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (bookmarks.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  itemCount: categories.length,
                  itemBuilder: (_, i) {
                    final cat      = categories[i];
                    final selected = cat == selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(
                            () => selectedCategory = cat),
                        child: AnimatedContainer(
                          duration:
                              const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? kPrimary
                                : Colors.white,
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                                color: selected
                                    ? kPrimary
                                    : Colors.grey.shade300),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                        color: kPrimary
                                            .withValues(
                                                alpha: 0.25),
                                        blurRadius: 6,
                                        offset:
                                            const Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : kPrimary)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          filtered.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())
              : SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) =>
                          _buildCard(filtered[i], i == 0),
                      childCount: filtered.length,
                    ),
                  ),
                ),
        ],
      ),
      floatingActionButton: Showcase(
        key: _addKey,
        title: 'Add a bookmark',
        description:
            'Tap + to save any URL with a title, category and reminder.',
        child: FloatingActionButton.extended(
          onPressed: () => _showBookmarkSheet(),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add Bookmark',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_border,
                  size: 48, color: kPrimary),
            ),
            const SizedBox(height: 24),
            const Text('No bookmarks yet',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Save links from any app and set reminders to revisit them later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: kTextSub, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showBookmarkSheet(),
              icon: const Icon(Icons.add),
              label: const Text('Add your first bookmark'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Bookmark bookmark, bool isFirst) {
    final reminder    = reminderMap[bookmark.id];
    final hasReminder = reminder != null;
    final color       = _platformColor(bookmark.platform);
    final icon        = _platformIcon(bookmark.platform);

    Widget alarmBtn = IconButton(
      icon: Icon(
        hasReminder ? Icons.alarm : Icons.alarm_add,
        color: hasReminder ? kGold : kAccent,
        size: 22,
      ),
      onPressed: () => _showReminderSheet(bookmark),
    );

    Widget deleteBtn = IconButton(
      icon: const Icon(Icons.delete_outline,
          color: Colors.red, size: 22),
      onPressed: () async {
        await repository.deleteBookmark(bookmark.id);
        await _loadBookmarks();
      },
    );

    if (isFirst) {
      alarmBtn = Showcase(
        key: _alarmKey,
        title: 'Set a reminder',
        description:
            'Tap to pick a date and time to be reminded.',
        child: alarmBtn,
      );
      deleteBtn = Showcase(
        key: _deleteKey,
        title: 'Delete',
        description: 'Remove a bookmark you no longer need.',
        child: deleteBtn,
      );
    }

    final cardContent = GestureDetector(
      onLongPress: () => _showEditSheet(bookmark),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final uri = Uri.parse(bookmark.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri,
                  mode: LaunchMode.externalApplication);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(bookmark.title,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(bookmark.url,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextSub),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    alarmBtn,
                    deleteBtn,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(bookmark.platform,
                          style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (hasReminder) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              kGold.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active,
                                size: 11,
                                color: kGold.darken()),
                            const SizedBox(width: 4),
                            Text(
                              _formatReminder(
                                  reminder.remindAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: kGold.darken()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isFirst) {
      return Showcase(
        key: _cardKey,
        title: 'Your bookmark',
        description:
            'Long press any bookmark to edit its title or category.',
        child: cardContent,
      );
    }
    return cardContent;
  }

  String _formatReminder(DateTime dt) {
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDay    = DateTime(dt.year, dt.month, dt.day);

    String dateStr;
    if (dtDay == today) {
      dateStr = 'Today';
    } else if (dtDay == tomorrow) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = '${dt.day}/${dt.month}/${dt.year}';
    }

    final h =
        dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final m      = dt.minute.toString().padLeft(2, '0');
    return '$dateStr · $h:$m $period';
  }
}

// ── Scroll wheel date/time picker ──────────────────────────────────────
class _DateTimePickerWidget extends StatefulWidget {
  final DateTime initialDateTime;
  final ValueChanged<DateTime> onChanged;

  const _DateTimePickerWidget({
    required this.initialDateTime,
    required this.onChanged,
  });

  @override
  State<_DateTimePickerWidget> createState() =>
      _DateTimePickerWidgetState();
}

class _DateTimePickerWidgetState
    extends State<_DateTimePickerWidget> {
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  late int  _month;
  late int  _day;
  late int  _year;
  late int  _hour;
  late int  _minute;
  late bool _isAM;

  late FixedExtentScrollController _mcCtrl;
  late FixedExtentScrollController _dcCtrl;
  late FixedExtentScrollController _ycCtrl;
  late FixedExtentScrollController _hcCtrl;
  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _perCtrl;

  List<int> get _years =>
      List.generate(3, (i) => DateTime.now().year + i);

  int get _daysInMonth => DateTime(_year, _month + 2, 0).day;

  @override
  void initState() {
    super.initState();
    final dt = widget.initialDateTime;
    _month  = dt.month - 1;
    _day    = dt.day;
    _year   = dt.year;
    _hour   = dt.hour == 0
        ? 12
        : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    _minute = dt.minute;
    _isAM   = dt.hour < 12;

    final yi = _years.indexOf(_year);
    _mcCtrl  = FixedExtentScrollController(initialItem: _month);
    _dcCtrl  =
        FixedExtentScrollController(initialItem: _day - 1);
    _ycCtrl  = FixedExtentScrollController(
        initialItem: yi < 0 ? 0 : yi);
    _hcCtrl  =
        FixedExtentScrollController(initialItem: _hour - 1);
    _minCtrl =
        FixedExtentScrollController(initialItem: _minute);
    _perCtrl = FixedExtentScrollController(
        initialItem: _isAM ? 0 : 1);
  }

  @override
  void dispose() {
    _mcCtrl.dispose();
    _dcCtrl.dispose();
    _ycCtrl.dispose();
    _hcCtrl.dispose();
    _minCtrl.dispose();
    _perCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final yi = _ycCtrl.hasClients
        ? min(_ycCtrl.selectedItem, _years.length - 1)
        : 0;
    final hour24 = _isAM
        ? (_hour == 12 ? 0 : _hour)
        : (_hour == 12 ? 12 : _hour + 12);
    widget.onChanged(DateTime(
      _years[yi],
      _month + 1,
      min(_day, _daysInMonth),
      hour24,
      _minute,
    ));
  }

  Widget _wheel(
    List<String> items,
    FixedExtentScrollController ctrl,
    ValueChanged<int> onChange, {
    double width = 52,
  }) {
    return SizedBox(
      width: width,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: ctrl,
            itemExtent: 44,
            perspective: 0.003,
            diameterRatio: 1.6,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) {
              onChange(i);
              _notify();
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: items.length,
              builder: (_, index) => Center(
                child: Text(
                  items[index],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
        _daysInMonth,
        (i) => (i + 1).toString().padLeft(2, '0'));
    final years = _years.map((y) => y.toString()).toList();
    final hours = List.generate(
        12, (i) => (i + 1).toString().padLeft(2, '0'));
    final mins = List.generate(
        60, (i) => i.toString().padLeft(2, '0'));

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: kPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _wheel(_months, _mcCtrl,
                (i) => setState(() => _month = i),
                width: 44),
            const SizedBox(width: 4),
            _wheel(days, _dcCtrl,
                (i) => setState(() => _day = i + 1),
                width: 36),
            const SizedBox(width: 4),
            _wheel(years, _ycCtrl,
                (i) => setState(() => _year = _years[i]),
                width: 50),
            Container(
              width: 1,
              height: 80,
              color: Colors.white.withValues(alpha: 0.2),
              margin:
                  const EdgeInsets.symmetric(horizontal: 8),
            ),
            _wheel(hours, _hcCtrl,
                (i) => setState(() => _hour = i + 1),
                width: 36),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(':',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white
                          .withValues(alpha: 0.8))),
            ),
            _wheel(mins, _minCtrl,
                (i) => setState(() => _minute = i),
                width: 36),
            const SizedBox(width: 4),
            _wheel(['AM', 'PM'], _perCtrl,
                (i) => setState(() => _isAM = i == 0),
                width: 32),
          ],
        ),
      ),
    );
  }
}
// ── Shared widgets ─────────────────────────────────────────────────────
class _BottomSheetContainer extends StatelessWidget {
  final Widget child;
  const _BottomSheetContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: child,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _GreenTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _GreenTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: kPrimary),
        hintStyle: TextStyle(color: Colors.grey.shade400),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: kPrimary, width: 2),
        ),
        filled: true,
        fillColor: kBg,
      ),
    );
  }
}

// ── Color extension ────────────────────────────────────────────────────
extension _ColorX on Color {
  Color darken([double amount = 0.2]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness(
            (hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}