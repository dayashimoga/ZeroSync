import 'package:flutter/material.dart';

/// Screen size categorization for responsive layout adaptation.
enum AdaptiveWindowSizeClass {
  compact,
  medium,
  expanded;

  static AdaptiveWindowSizeClass fromWidth(double width) {
    if (width < 600.0) return AdaptiveWindowSizeClass.compact;
    if (width < 840.0) return AdaptiveWindowSizeClass.medium;
    return AdaptiveWindowSizeClass.expanded;
  }
}

/// Adaptive split-pane layout scaffold supporting phones, foldables, and tablets.
///
/// Behavior:
/// - Single-column mobile (< 720px): Renders an [IndexedStack] tabbed interface
///   that keeps the primary camera feed persistently alive in memory across tab changes.
/// - Dual-pane tablet (>= 720px): Renders a persistent side-by-side layout with the
///   camera scanner on the primary pane and the history / inspection details on the secondary pane.
class AdaptiveSplitPaneScaffold extends StatefulWidget {
  /// Primary pane widget (typically persistent camera scanner viewport).
  final Widget primaryPane;

  /// Secondary pane widget (history list, batch manager, or URL inspector).
  final Widget secondaryPane;

  /// Optional app bar title or custom widget.
  final Widget? title;

  /// Actions displayed in the app bar.
  final List<Widget>? actions;

  /// Width threshold in logical pixels above which dual-pane mode is activated.
  final double splitBreakpoint;

  /// Ratio of primary pane width to total width in dual-pane mode (0.3..0.7).
  final double primaryRatio;

  /// Label for primary tab in compact mobile navigation.
  final String primaryTabLabel;

  /// Label for secondary tab in compact mobile navigation.
  final String secondaryTabLabel;

  /// Icon for primary tab in compact mobile navigation.
  final IconData primaryTabIcon;

  /// Icon for secondary tab in compact mobile navigation.
  final IconData secondaryTabIcon;

  const AdaptiveSplitPaneScaffold({
    super.key,
    required this.primaryPane,
    required this.secondaryPane,
    this.title,
    this.actions,
    this.splitBreakpoint = 720.0,
    this.primaryRatio = 0.55,
    this.primaryTabLabel = 'Scanner',
    this.secondaryTabLabel = 'Vault',
    this.primaryTabIcon = Icons.qr_code_scanner,
    this.secondaryTabIcon = Icons.history,
  }) : assert(primaryRatio >= 0.3 && primaryRatio <= 0.7, 'primaryRatio must be between 0.3 and 0.7');

  @override
  State<AdaptiveSplitPaneScaffold> createState() => _AdaptiveSplitPaneScaffoldState();
}

class _AdaptiveSplitPaneScaffoldState extends State<AdaptiveSplitPaneScaffold> {
  int _activeTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDualPane = constraints.maxWidth >= widget.splitBreakpoint;

        return Scaffold(
          appBar: AppBar(
            title: widget.title,
            actions: widget.actions,
            elevation: 0,
          ),
          body: isDualPane
              ? _buildDualPaneLayout(constraints.maxWidth)
              : _buildSinglePaneIndexedStack(),
          bottomNavigationBar: isDualPane
              ? null
              : NavigationBar(
                  selectedIndex: _activeTabIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _activeTabIndex = index;
                    });
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(widget.primaryTabIcon),
                      label: widget.primaryTabLabel,
                    ),
                    NavigationDestination(
                      icon: Icon(widget.secondaryTabIcon),
                      label: widget.secondaryTabLabel,
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// Persistent side-by-side dual-pane layout for tablets and unfolded foldables.
  Widget _buildDualPaneLayout(double totalWidth) {
    final theme = Theme.of(context);
    final primaryWidth = totalWidth * widget.primaryRatio;
    final secondaryWidth = totalWidth - primaryWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary pane (Scanner preview)
        SizedBox(
          width: primaryWidth,
          child: widget.primaryPane,
        ),

        // Vertical divider separating the two active workspaces
        VerticalDivider(
          width: 1.0,
          thickness: 1.0,
          color: theme.colorScheme.outlineVariant,
        ),

        // Secondary pane (History / Inspector)
        SizedBox(
          width: secondaryWidth - 1.0,
          child: widget.secondaryPane,
        ),
      ],
    );
  }

  /// Mobile single-pane view preserving the primary camera widget using [IndexedStack].
  /// This prevents disposing and restarting the camera hardware sensor when switching tabs.
  Widget _buildSinglePaneIndexedStack() {
    return IndexedStack(
      index: _activeTabIndex,
      children: [
        widget.primaryPane,
        widget.secondaryPane,
      ],
    );
  }
}

