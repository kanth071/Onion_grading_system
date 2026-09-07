/// Lets a pushed screen (e.g. ResultsScreen) tell RootShell which tab to
/// land on after popping back, without threading a callback through every
/// intermediate screen in the push chain (Upload -> Processing -> Results,
/// or Dashboard/History -> Results). RootShell registers its handler once
/// in initState; any screen can call AppNav.goToTab(...) before popping.
class AppNav {
  static void Function(int index)? _switchTab;
  static void register(void Function(int index) fn) => _switchTab = fn;
  static void goToTab(int index) => _switchTab?.call(index);
}
