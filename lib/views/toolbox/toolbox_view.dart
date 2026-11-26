import 'package:material_ui/material_ui.dart';
import '../../services/status_bar_service.dart';
import 'toolbox_tool_registry.dart';

class ToolboxView extends StatelessWidget {
  const ToolboxView({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = ToolboxToolRegistry.tools;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: DefaultTabController(
        length: tools.length,
        child: _ToolboxTabListener(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerHeight: 1,
                    dividerColor: colorScheme.outlineVariant,
                    indicatorColor: colorScheme.primary,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    labelStyle: Theme.of(context).textTheme.labelLarge,
                    tabs: [
                      for (final tool in tools)
                        Tab(
                          height: 40,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(tool.icon, size: 16),
                              const SizedBox(width: 6),
                              Text(tool.title),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [for (final tool in tools) tool.builder(context)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 监听 DefaultTabController 索引变化，同步到 StatusBarService
class _ToolboxTabListener extends StatefulWidget {
  const _ToolboxTabListener({required this.child});
  final Widget child;

  @override
  State<_ToolboxTabListener> createState() => _ToolboxTabListenerState();
}

class _ToolboxTabListenerState extends State<_ToolboxTabListener> {
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newCtrl = DefaultTabController.of(context);
    if (newCtrl != _tabController) {
      _tabController?.removeListener(_onTabChanged);
      _tabController = newCtrl;
      _tabController!.addListener(_onTabChanged);
      _onTabChanged();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController != null) {
      StatusBarService().setActiveToolboxTool(
        ToolboxToolRegistry.idAt(_tabController!.index),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
