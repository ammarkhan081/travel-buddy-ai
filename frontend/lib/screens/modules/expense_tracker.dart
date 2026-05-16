import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'add_expense.dart';
import '../../services/fastapi_service.dart';
import '../../utils/ui_utils.dart';

class ExpenseTracker extends StatefulWidget {
  const ExpenseTracker({super.key});

  @override
  State<ExpenseTracker> createState() => _ExpenseTrackerState();
}

class _ExpenseTrackerState extends State<ExpenseTracker> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expense Tracker')),
        body: const Center(child: Text('Please log in to view expenses')),
      );
    }

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        backgroundColor: const Color(0xFF1E66F5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddExpense()),
              );
              if (result == true) {
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: FastApiService().get('/api/expenses/').then((res) => res as List<dynamic>),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allExpenses = snapshot.data ?? [];
          
          // Filter and sort
          final expenses = allExpenses.where((data) {
            final dateStr = data['date'] as String?;
            if (dateStr == null) return false;
            final expenseDate = DateTime.tryParse(dateStr);
            if (expenseDate == null) return false;
            return expenseDate.isAfter(startOfMonth.subtract(const Duration(days: 1)));
          }).toList()
            ..sort((a, b) {
              final aDate = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
              final bDate = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
              return bDate.compareTo(aDate);
            });

          final total = expenses.fold<double>(
            0,
            (sum, data) => sum + (data['amount'] as num).toDouble(),
          );

          // Calculate category totals
          final categoryTotals = <String, double>{};
          for (var data in expenses) {
            final category = data['category'] ?? 'Other';
            final amount = (data['amount'] as num).toDouble();
            categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
          }

          final sortedCategories = categoryTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Expenses',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E66F5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'This Month (${expenses.length} expenses)',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (sortedCategories.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Expense Breakdown',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: _buildPieChartSections(sortedCategories),
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...sortedCategories.map((entry) => _buildExpenseCategory(
                        entry.key,
                        entry.value,
                        _getCategoryColor(entry.key),
                      )),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Recent Expenses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                if (expenses.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No expenses this month',
                          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height:30),
                        Text(
                          'Tap the + button to add your first expense',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...expenses.take(10).map((data) {
                    return _buildExpenseItem(context, data['id'].toString(), data);
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(List<MapEntry<String, double>> categories) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.green,
      Colors.teal,
      Colors.pink,
    ];

    return categories.asMap().entries.map((entry) {
      final index = entry.key;
      final category = entry.value;
      return PieChartSectionData(
        value: category.value,
        title: category.key.length > 8 ? '${category.key.substring(0, 8)}...' : category.key,
        color: colors[index % colors.length],
        radius: 60,
      );
    }).toList();
  }

  Color _getCategoryColor(String category) {
    final colors = {
      'Food & Dining': Colors.red,
      'Transportation': Colors.blue,
      'Shopping': Colors.purple,
      'Bills & Utilities': Colors.orange,
      'Entertainment': Colors.green,
      'Other': Colors.teal,
    };
    return colors[category] ?? Colors.grey;
  }

  Widget _buildExpenseCategory(String category, double amount, Color color) {
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
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.circle, color: color, size: 24),
        ),
        title: Text(category),
        trailing: Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseItem(BuildContext context, String docId, Map<String, dynamic> data) {
    final amount = (data['amount'] as num).toDouble();
    final category = data['category'] ?? 'Other';
    final description = data['description'] ?? '';
    final date = DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();

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
            color: _getCategoryColor(category).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.receipt, color: _getCategoryColor(category), size: 24),
        ),
        title: Text(description.isEmpty ? category : description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category),
            Text(
              DateFormat('MMM dd, yyyy').format(date),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\$${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) => _deleteExpense(docId),
            ),
          ],
        ),

      ),
    );
  }

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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
          UIFeedback.showSnackBar(context, 'Error deleting expense: $e', isError: true);
        }
      }
    }
  }
}


