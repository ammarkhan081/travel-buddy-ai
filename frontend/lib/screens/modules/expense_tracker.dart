import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';
import '../../widgets/module_fab.dart';
import 'add_expense.dart';

/// Expense Tracker — total + by-category + recent expenses.
/// Visuals match the dashboard. Backend calls (GET / DELETE /api/expenses)
/// and AddExpense navigation are preserved exactly.
class ExpenseTracker extends StatefulWidget {
  const ExpenseTracker({super.key});

  @override
  State<ExpenseTracker> createState() => _ExpenseTrackerState();
}

class _ExpenseTrackerState extends State<ExpenseTracker> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _categoryFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              title: 'Expenses',
              subtitle: 'Sign in to view your expenses',
              onBack: () => Navigator.maybePop(context),
            ),
            const Expanded(
              child: Center(child: Text('Please log in to view expenses')),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: ModuleFab(
        icon: Icons.add,
        label: 'Add Expense',
        minWidth: 156,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddExpense()),
          );
          if (result == true) setState(() {});
        },
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'Expenses',
            subtitle: DateFormat('MMMM yyyy').format(now),
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: FastApiService()
                  .get('/api/expenses/')
                  .then((res) => res as List<dynamic>),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        icon: Icons.error_outline,
                        title: 'Couldn\'t load expenses',
                        subtitle: 'Pull down to retry.\n${snapshot.error}',
                      ),
                    ),
                  );
                }

                final allExpenses = (snapshot.data ?? const [])
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList();

                // This-month filter + sort newest first
                final monthExpenses =
                    allExpenses.where((data) {
                      final dateStr = data['date'] as String?;
                      if (dateStr == null) return false;
                      final d = DateTime.tryParse(dateStr);
                      if (d == null) return false;
                      return d.isAfter(
                        startOfMonth.subtract(const Duration(days: 1)),
                      );
                    }).toList()..sort((a, b) {
                      final aD =
                          DateTime.tryParse((a['date'] ?? '').toString()) ??
                          DateTime(2000);
                      final bD =
                          DateTime.tryParse((b['date'] ?? '').toString()) ??
                          DateTime(2000);
                      return bD.compareTo(aD);
                    });

                final categoryTotals = <String, double>{};
                for (final e in monthExpenses) {
                  final cat = (e['category'] ?? 'other').toString();
                  final amt = (e['amount'] as num? ?? 0).toDouble();
                  categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amt;
                }
                final sortedCats = categoryTotals.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                final total = monthExpenses.fold<double>(
                  0,
                  (s, d) => s + ((d['amount'] as num? ?? 0).toDouble()),
                );

                // Apply category filter for the list section only
                final shownExpenses = _categoryFilter == 'All'
                    ? monthExpenses
                    : monthExpenses
                          .where(
                            (e) =>
                                (e['category'] ?? '').toString() ==
                                _categoryFilter,
                          )
                          .toList();

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildSummaryCard(total, monthExpenses.length, isDark),
                      const SizedBox(height: 18),
                      if (sortedCats.isNotEmpty) ...[
                        AppSectionTitle(
                          title: 'Breakdown',
                          icon: Icons.donut_large_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildBreakdownCard(sortedCats, total, isDark),
                        const SizedBox(height: 18),
                      ],
                      // Category filter chips
                      _buildCategoryChips([
                        'All',
                        ...sortedCats.map((e) => e.key),
                      ]),
                      const SizedBox(height: 12),
                      AppSectionTitle(
                        title: _categoryFilter == 'All'
                            ? 'Recent Expenses'
                            : 'Recent · $_categoryFilter',
                        icon: Icons.receipt_long_rounded,
                      ),
                      const SizedBox(height: 12),
                      if (shownExpenses.isEmpty)
                        AppEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No expenses this month',
                          subtitle:
                              'Tap "Add Expense" to track your first expense.',
                        )
                      else
                        ...shownExpenses
                            .take(20)
                            .map(
                              (data) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ExpenseTile(
                                  data: data,
                                  onDelete: () =>
                                      _deleteExpense(data['id'].toString()),
                                ),
                              ),
                            ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary card ───────────────────────────────────────────────────────────
  Widget _buildSummaryCard(double total, int count, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 6),
              const Text(
                'Total this month',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count entries',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'PKR ${_formatAmount(total)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat('d MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double v) {
    final f = NumberFormat('#,##0.00');
    return f.format(v);
  }

  // ── Breakdown ──────────────────────────────────────────────────────────────
  Widget _buildBreakdownCard(
    List<MapEntry<String, double>> cats,
    double total,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: _pieSections(cats),
                sectionsSpace: 3,
                centerSpaceRadius: 48,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...cats.take(5).map((entry) {
            final color = _categoryColor(entry.key);
            final pct = total == 0 ? 0.0 : (entry.value / total) * 100;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _categoryLabel(entry.key),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'PKR ${_formatAmount(entry.value)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<PieChartSectionData> _pieSections(List<MapEntry<String, double>> cats) {
    final total = cats.fold<double>(0, (s, e) => s + e.value);
    return cats.map((entry) {
      final pct = total == 0 ? 0.0 : (entry.value / total) * 100;
      return PieChartSectionData(
        value: entry.value,
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        color: _categoryColor(entry.key),
        radius: 50,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      );
    }).toList();
  }

  // ── Category chips ─────────────────────────────────────────────────────────
  Widget _buildCategoryChips(List<String> cats) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final active = cat == _categoryFilter;
          final color = cat == 'All' ? AppColors.primary : _categoryColor(cat);
          return Material(
            color: active
                ? color
                : (isDark ? AppColors.surfaceDarkElevated : Colors.white),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => setState(() => _categoryFilter = cat),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _categoryIcon(cat),
                      size: 14,
                      color: active ? Colors.white : color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _categoryLabel(cat),
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary),
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Delete confirmation ────────────────────────────────────────────────────
  Future<void> _deleteExpense(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FastApiService().delete('/api/expenses/$docId');
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Expense deleted');
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          UIFeedback.showSnackBar(
            context,
            'Error deleting expense: $e',
            isError: true,
          );
        }
      }
    }
  }

  // ── Category palette ───────────────────────────────────────────────────────
  static Color _categoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'food':
      case 'food & dining':
      case 'restaurant':
      case 'cafe':
      case 'dining':
        return const Color(0xFFE67934);
      case 'transport':
      case 'transportation':
      case 'taxi':
      case 'uber':
      case 'flight':
      case 'train':
      case 'bus':
        return const Color(0xFF4F7AFF);
      case 'accommodation':
      case 'hotel':
      case 'hostel':
      case 'airbnb':
        return const Color(0xFF8E5DFF);
      case 'shopping':
      case 'souvenir':
      case 'clothing':
        return const Color(0xFFE94E66);
      case 'entertainment':
      case 'tour':
      case 'museum':
      case 'activity':
        return const Color(0xFFE89B2C);
      case 'bills & utilities':
      case 'bills':
        return const Color(0xFF20B2C9);
      default:
        return const Color(0xFF7B5AFF);
    }
  }

  static String _categoryLabel(String cat) {
    if (cat.isEmpty) return 'Other';
    return cat[0].toUpperCase() + cat.substring(1).toLowerCase();
  }

  static IconData _categoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'all':
        return Icons.apps_rounded;
      case 'food':
      case 'food & dining':
      case 'restaurant':
      case 'cafe':
      case 'dining':
        return Icons.restaurant_rounded;
      case 'transport':
      case 'transportation':
      case 'taxi':
      case 'uber':
        return Icons.local_taxi_rounded;
      case 'flight':
        return Icons.flight_rounded;
      case 'train':
        return Icons.train_rounded;
      case 'bus':
        return Icons.directions_bus_rounded;
      case 'accommodation':
      case 'hotel':
      case 'hostel':
      case 'airbnb':
        return Icons.apartment_rounded;
      case 'shopping':
      case 'souvenir':
      case 'clothing':
        return Icons.shopping_bag_rounded;
      case 'entertainment':
      case 'tour':
      case 'museum':
      case 'activity':
        return Icons.theater_comedy_rounded;
      case 'bills':
      case 'bills & utilities':
        return Icons.receipt_long_rounded;
      default:
        return Icons.label_rounded;
    }
  }
}

/// Single expense list item.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.data, required this.onDelete});
  final Map<String, dynamic> data;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amount = (data['amount'] as num? ?? 0).toDouble();
    final currency = (data['currency'] ?? 'PKR').toString().toUpperCase();
    final category = (data['category'] ?? 'other').toString();
    final description = (data['description'] ?? '').toString();
    final dt =
        DateTime.tryParse((data['date'] ?? '').toString()) ?? DateTime.now();
    final color = _ExpenseTrackerState._categoryColor(category);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: () {}, // detail view could go here later
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    _ExpenseTrackerState._categoryIcon(category),
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        description.isEmpty
                            ? _ExpenseTrackerState._categoryLabel(category)
                            : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_ExpenseTrackerState._categoryLabel(category)} · ${DateFormat('MMM d').format(dt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$currency ${NumberFormat('#,##0.00').format(amount)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.danger,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
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
