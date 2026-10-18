import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fund/fund_page.dart';
import '../periods/periods_page.dart';
import '../stats/stats_page.dart';
import '../templates/templates_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _pages = <Widget>[PeriodsPage(), FundPage(), TemplatesPage(), StatsPage()];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            setState(() => _index = i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'Períodos'),
            NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings_rounded), label: 'Caja'),
            NavigationDestination(icon: Icon(Icons.copy_all_outlined), selectedIcon: Icon(Icons.copy_all_rounded), label: 'Plantillas'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Resumen'),
          ],
        ),
      );
}
