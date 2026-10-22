import 'package:flutter/material.dart';

abstract final class FundWellBreakpoints {
  static const double tablet = 720;
  static const double desktop = 1100;

  static bool isTablet(double width) => width >= tablet && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

class FundWellDestination {
  const FundWellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    this.maxWidth = 1400,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

class AdaptiveNavigationShell extends StatelessWidget {
  const AdaptiveNavigationShell({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    required this.onNotifications,
    this.applicationName = 'FundWell',
    this.desktopHeader,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FundWellDestination> destinations;
  final Widget body;
  final VoidCallback onNotifications;
  final String applicationName;
  final Widget? desktopHeader;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = FundWellBreakpoints.isDesktop(constraints.maxWidth);
      final tablet = FundWellBreakpoints.isTablet(constraints.maxWidth);
      if (!desktop && !tablet) {
        return Scaffold(
          key: const Key('mobile-navigation-shell'),
          appBar: AppBar(
            title: Text(applicationName),
            actions: [_notificationButton()],
          ),
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
          ),
        );
      }

      return Scaffold(
        key: Key(
          desktop ? 'desktop-navigation-shell' : 'tablet-navigation-shell',
        ),
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                key: const Key('primary-navigation-rail'),
                extended: desktop,
                minExtendedWidth: 264,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: desktop ? null : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  child: desktop
                      ? SizedBox(
                          width: 216,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                applicationName,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (desktopHeader != null) ...[
                                const SizedBox(height: 18),
                                desktopHeader!,
                              ],
                            ],
                          ),
                        )
                      : const Icon(Icons.account_balance_wallet_outlined),
                ),
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 64,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            if (desktop)
                              Expanded(
                                child: Text(
                                  destinations[selectedIndex].label,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              )
                            else
                              const Spacer(),
                            _notificationButton(),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ResponsiveContent(
                        maxWidth: 1440,
                        child: FocusTraversalGroup(child: body),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _notificationButton() => IconButton(
    icon: const Icon(Icons.notifications_outlined),
    tooltip: 'Notifications',
    onPressed: onNotifications,
  );
}
