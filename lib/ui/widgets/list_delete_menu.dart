import 'package:material_ui/material_ui.dart';

/// 列表条目的删除入口；右键只打开菜单，不改变当前选中项。
class ListDeleteMenu extends StatelessWidget {
  const ListDeleteMenu({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (details) async {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final point = overlay.globalToLocal(details.globalPosition);
      final selected = await showMenu<bool>(
        context: context,
        position: RelativeRect.fromRect(
          point & Size.zero,
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem(
            value: true,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  '删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ),
        ],
      );
      if (selected == true && context.mounted) onDelete();
    },
    child: child,
  );
}
