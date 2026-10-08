import 'package:flutter/material.dart';

export 'dashboard/home_screen.dart';
export 'expenses/expenses_screen.dart';
export 'revenue/revenue_screen.dart';

class VendorsScreen extends StatelessWidget {
  const VendorsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Vendors\n\nVendor spend will appear here.',
      textAlign: TextAlign.center,
    ),
  );
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'More',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 20),
        Text('Demo Restaurant Group'),
        SizedBox(height: 8),
        Text('Account settings and sign out will appear here.'),
      ],
    ),
  );
}
