import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_nav.dart';
import 'theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/history_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.instance.load();
  runApp(const OnionGradingApp());
}

class OnionGradingApp extends StatelessWidget {
  const OnionGradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GradeLens AI',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootShell(),
    );
  }
}

const _destinations = [
  (icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: 'Dashboard'),
  (icon: Icons.camera_alt_outlined, selectedIcon: Icons.camera_alt, label: 'New Inspection'),
  (icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'Inspection History'),
  (icon: Icons.show_chart_outlined, selectedIcon: Icons.show_chart, label: 'Analytics'),
  (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
];

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;
  int _dashboardRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    AppNav.register(_goTo);
  }

  void _goTo(int index) {
    setState(() {
      _tabIndex = index;
      // Dashboard's "Recent Inspections" is fetched once per instance - since
      // IndexedStack keeps it alive across tab switches, a freshly completed
      // inspection wouldn't show up otherwise until the whole app restarted.
      // A new key forces a fresh instance (and fresh fetch) every visit.
      if (index == 0) _dashboardRefreshKey++;
    });
  }

  /// Tapping the profile row opens Settings, where the server URL now lives
  /// as a proper field - a raw "paste a URL" popup dialog isn't something
  /// that belongs behind a profile tap in front of an evaluator.
  void _openProfile() {
    _goTo(4);
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ApiClient.instance.baseUrl;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 220,
            color: Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.eco, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('GradeLens AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            Text('Onion Quality Platform', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _tabIndex,
                    onDestinationSelected: _goTo,
                    labelType: NavigationRailLabelType.none,
                    extended: true,
                    minExtendedWidth: 220,
                    backgroundColor: Colors.white,
                    destinations: _destinations
                        .map((d) => NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ))
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _openProfile,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const CircleAvatar(radius: 15, backgroundColor: AppColors.green, child: Text('PO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('Procurement Officer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(_destinations[_tabIndex].label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      KeyedSubtree(
                          key: ValueKey('dash-$baseUrl-$_dashboardRefreshKey'),
                          child: DashboardScreen(
                            onNewInspection: () => _goTo(1),
                            onViewAllHistory: () => _goTo(2),
                          )),
                      const UploadScreen(embedded: true),
                      KeyedSubtree(key: ValueKey('history-$baseUrl'), child: const HistoryScreen(embedded: true)),
                      KeyedSubtree(key: ValueKey('analytics-$baseUrl'), child: const AnalyticsScreen()),
                      KeyedSubtree(key: ValueKey('settings-$baseUrl'), child: const SettingsScreen(embedded: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
