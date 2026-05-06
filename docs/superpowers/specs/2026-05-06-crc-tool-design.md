# CRC 计算工具设计规格

## 目标

在工具箱中新增"CRC计算"工具，提供循环冗余校验计算能力。参考 https://www.ip33.com/crc.html 的功能设计，支持 Hex/ASCII 文本/二进制文件三种数据输入方式，内置 21 种常见 CRC 算法预设模型，并支持完全自定义 CRC 参数。同时在预设模型选择区域旁提供"关于"悬浮窗，展示所有预设模型的完整参数对照表。

## 范围

- 在工具箱注册表中新增"CRC计算"二级 Tab。
- 实现 21 种预设 CRC 算法模型（与 ip33.com 一致）。
- 支持三种数据输入模式：Hex 输入、ASCII 文本输入、二进制文件导入。
- 支持完全自定义 CRC 参数（WIDTH、POLY、INIT、XOROUT、REFIN、REFOUT）。
- 实时计算并输出三种格式结果：Hex、Bin、Dec。
- 预设模型选择区域旁提供"关于"图标，悬浮/点击显示参数模型对照表。
- 纯逻辑 CRC 计算引擎放在 Service 层，零 Flutter 依赖，可独立单元测试。

不在本轮范围内：

- CRC 校验（只计算，不验证）。
- 批量处理多个文件。
- 自定义多项式公式编辑（仅支持16进制参数输入）。
- 结果导出到文件。

## 用户体验方向

CRC 计算工具定位为轻量、即时响应的计算器式工具。延续工具箱现有的左右分栏桌面工作台布局，左侧操作区配置参数，右侧结果区呈现计算输出。

核心交互原则：

- **即时反馈**：任何输入变化（数据、参数、预设选择）立即触发重新计算并更新结果。
- **模式切换自然**：Hex/ASCII/文件三种输入模式通过 SegmentedButton 或 TabBar 切换，当前模式的数据切换时不丢失。
- **预设覆盖清晰**：选择预设模型时自动更新所有参数并禁用自定义参数区；切回"自定义"时恢复上次自定义参数值。
- **透明参考**：通过"关于"悬浮窗可随时查看各预设模型的参数，无需离开工具或打开浏览器。

## 总体布局

### 桌面宽屏布局（>= 860px）

左右分栏：

- 左侧操作栏宽 320px：
  - 上部：[Card] 数据输入（Hex/ASCII/文件 Tab 切换 + 对应输入控件）
  - 下部：[Card] CRC 参数（预设模型下拉 + 关于图标 + 自定义参数区）
- 右侧展示区占据剩余空间，内容根据当前输入模式不同：
  - **文件模式**（已导入文件时）：上下分栏
    - 上部：文件内容预览区，复用现有 `HexAsciiViewer` 组件（只读模式），显示导入文件的 HEX + ASCII 内容
    - 下部：[Card] 计算结果（HEX / Bin / Dec 三行输出）
  - **Hex/ASCII 模式 / 文件未导入时**：仅显示 [Card] 计算结果

### 窄屏布局（< 860px）

上下分栏：

- 上方：数据输入 Card + CRC 参数 Card（垂直堆叠）
- 下方：计算结果 Card（文件模式下，文件预览区在计算结果 Card 上方）

### "关于"悬浮窗布局

- 位置：预设模型 DropdownButton 右侧的 ⓘ 图标触发
- 弹窗内容：21 种预设 CRC 模型的完整参数表格（DataTable）
  - 列：名称、Width、Poly、Init、XorOut、RefIn、RefOut
- 弹窗样式：圆角 Card，带轻微阴影，最大高度受限且内部可滚动

关于图标交互规则：

| 交互 | 行为 |
|------|------|
| 鼠标悬浮进入图标 | 显示悬浮弹窗 |
| 鼠标移出图标 + 移出弹窗 | 若未常驻则隐藏弹窗 |
| 点击图标（未常驻） | 弹窗常驻显示 |
| 点击图标（已常驻） | 关闭弹窗 |
| 点击弹窗外空白区域 | 关闭弹窗 |

## 数据输入模式

### Hex 输入
- 多行 TextField，输入16进制字符串。
- 自动过滤空格、换行、制表符。
- 支持大小写混用，如 `31 32 33 34` 或 `0x31 0x32` 或 `31323334`。
- 提示文本示例：`例如: 31 32 33 34`
- 输入非法字符时（非0-9, a-f, A-F, 空格, 换行），计算结果区显示错误提示。

### ASCII 输入
- 单行或多行 TextField，输入任意文本。
- 内部使用 UTF-8 编码转换为字节序列。
- 提示文本示例：`例如: hello world`
- 空输入时不计算，结果区显示占位提示。

### 文件导入
- 复用现有 `FileDropZone` 通用组件。
- 接受任意文件（不限扩展名）。
- 导入后显示文件名和文件大小。
- 文件字节作为 CRC 计算输入。
- 可点击重新导入覆盖当前文件。

### 文件预览
- 文件模式导入文件后，右侧展示区上部显示文件内容预览。
- 预览使用现有 `HexAsciiViewer` 组件（只读模式，`onByteChanged` 为 `null`）。
- 预览区与文件列表联动：显示当前导入文件的完整 HEX + ASCII 内容。
- 预览区高度约占右侧展示区的 60%，与下部计算结果 Card 通过可拖拽分隔条或固定比例分栏。
- 未导入文件时预览区隐藏，右侧仅显示计算结果 Card。

### 模式切换
- 使用 TabBar 或 SegmentedButton 在三种模式间切换。
- 各模式的数据独立保存，切换时不丢失。
- 仅当前选中模式的数据参与 CRC 计算。

## CRC 参数模型

### 预设模型（21种）

从 ip33.com 提取的完整预设列表：

| 名称 | Width | Poly | Init | XorOut | RefIn | RefOut |
|------|-------|------|------|--------|-------|--------|
| CRC-4/ITU | 4 | 0x03 | 0x00 | 0x00 | true | true |
| CRC-5/EPC | 5 | 0x09 | 0x09 | 0x00 | false | false |
| CRC-5/ITU | 5 | 0x15 | 0x00 | 0x00 | true | true |
| CRC-5/USB | 5 | 0x05 | 0x1F | 0x1F | true | true |
| CRC-6/ITU | 6 | 0x03 | 0x00 | 0x00 | true | true |
| CRC-7/MMC | 7 | 0x09 | 0x00 | 0x00 | false | false |
| CRC-8 | 8 | 0x07 | 0x00 | 0x00 | false | false |
| CRC-8/ITU | 8 | 0x07 | 0x00 | 0x55 | false | false |
| CRC-8/ROHC | 8 | 0x07 | 0xFF | 0x00 | true | true |
| CRC-8/MAXIM | 8 | 0x31 | 0x00 | 0x00 | true | true |
| CRC-16/IBM | 16 | 0x8005 | 0x0000 | 0x0000 | true | true |
| CRC-16/MAXIM | 16 | 0x8005 | 0x0000 | 0xFFFF | true | true |
| CRC-16/USB | 16 | 0x8005 | 0xFFFF | 0xFFFF | true | true |
| CRC-16/MODBUS | 16 | 0x8005 | 0xFFFF | 0x0000 | true | true |
| CRC-16/CCITT | 16 | 0x1021 | 0x0000 | 0x0000 | true | true |
| CRC-16/CCITT-FALSE | 16 | 0x1021 | 0xFFFF | 0x0000 | false | false |
| CRC-16/X25 | 16 | 0x1021 | 0xFFFF | 0xFFFF | true | true |
| CRC-16/XMODEM | 16 | 0x1021 | 0x0000 | 0x0000 | false | false |
| CRC-16/DNP | 16 | 0x3D65 | 0x0000 | 0xFFFF | true | true |
| CRC-32 | 32 | 0x04C11DB7 | 0xFFFFFFFF | 0xFFFFFFFF | true | true |
| CRC-32/MPEG-2 | 32 | 0x04C11DB7 | 0xFFFFFFFF | 0x00000000 | false | false |

### 自定义参数
- WIDTH：DropdownButton，选项 1-32。
- POLY：TextField，16进制输入（不含省略的最高位）。
- INIT：TextField，16进制输入。
- XOROUT：TextField，16进制输入。
- REFIN：Switch 开关。
- REFOUT：Switch 开关。

参数输入合法性验证：
- 16进制字段只接受 0-9, a-f, A-F, 0x 前缀。
- POLY/INIT/XOROUT 的值范围受 WIDTH 约束（超出部分给出警告）。
- 非法输入时暂不触发计算，显示错误提示。

### 预设与自定义切换
- 选择预设模型时：自定义参数区隐藏（或只读显示当前预设的参数值），计算结果基于预设参数。
- 选择"自定义"时：恢复上次自定义参数值，显示自定义参数输入区。
- Dropdown 选项列表：["自定义", "CRC-4/ITU", "CRC-5/EPC", ..., "CRC-32/MPEG-2"]

## CRC 计算引擎

### 算法规范

采用逐位计算法（Bit-by-Bit），支持任意 1-32 位宽度的 CRC。

伪代码：

```
crc = INIT
mask = (1 << WIDTH) - 1
poly = POLY | (1 << WIDTH)   // 补回被省略的最高位
topBit = 1 << (WIDTH - 1)

for each byte in data:
    b = REFIN ? reverse_bits(byte, 8) : byte
    
    if WIDTH > 8:
        crc = crc ^ (b << (WIDTH - 8))
    else:
        crc = crc ^ b
    
    for i in 0..7:
        if (crc & topBit) != 0:
            crc = ((crc << 1) ^ poly) & mask
        else:
            crc = (crc << 1) & mask

if REFOUT:
    crc = reverse_bits(crc, WIDTH)

crc = (crc ^ XOROUT) & mask
return crc
```

### 边界情况

- 空数据：返回 INIT 经 REFOUT 和 XOROUT 处理后的值（即 `(init ^ xorout) & mask`，若 refout 为 true 则为 `(reverse_bits(init, width) ^ xorout) & mask`）。
- WIDTH=1..8：输入字节不左移对齐，直接与 crc 异或。
- WIDTH=9..32：输入字节左移 (WIDTH-8) 位对齐到 crc 高位。
- POLY 值：存储时已去掉隐含的最高位（如 CRC-32 存 0x04C11DB7），计算时内部补回。

### 结果格式化

计算结果的 `int` 值按当前 WIDTH 格式化输出：

- **Hex**：`0x` + 大写16进制，宽度补齐（如 CRC-16 → `0x1A2B`，CRC-32 → `0x1A2B3C4D`）。
- **Bin**：二进制字符串，按 WIDTH 补齐，每4位加空格分隔。
- **Dec**：十进制数字字符串。

## 关于悬浮窗

### 触发组件

- ⓘ 图标（`Icons.info_outline`），位于预设模型 DropdownButton 同一行右侧。
- 图标颜色：使用 `colorScheme.primary`。
- Tooltip / 悬浮时临时显示。

### 弹窗内容

使用 `DataTable` 渲染 21 种预设模型参数对照表：

- 列：名称（Name）、宽度（Width）、多项式（Poly）、初始值（Init）、异或值（XorOut）、输入反转（RefIn）、输出反转（RefOut）。
- RefIn/RefOut 列显示 ✓ / ✗。
- 最大高度约 400px，超出可滚动。
- 当前选中的预设行高亮。

### 显示逻辑（在 ViewModel 中管理）

```
状态变量：
- _isAboutPopupPinned: bool   // 点击图标切换
- _isAboutPopupHovered: bool  // 鼠标悬浮在图标或弹窗上

显示条件：showAboutPopup = _isAboutPopupPinned || _isAboutPopupHovered
```

交互实现：

- 图标 `MouseRegion(onEnter:)` → `_isAboutPopupHovered = true` → `notifyListeners()`
- 图标 `MouseRegion(onExit:)` → `_isAboutPopupHovered = false` → `notifyListeners()`
- 弹窗 `MouseRegion(onEnter:)` → `_isAboutPopupHovered = true`（保持显示）
- 弹窗 `MouseRegion(onExit:)` → `_isAboutPopupHovered = false`（若未常驻则关闭）
- 图标 `GestureDetector(onTap:)` → `_isAboutPopupPinned = !_isAboutPopupPinned` → `notifyListeners()`
- 点击空白区域 → 通过 `Listener` 或点击弹窗外层时 → `_isAboutPopupPinned = false`

### 弹窗定位

使用 `Overlay.of(context).insert()` 在图标下方插入弹窗。通过 `CompositedTransformTarget/Follower` 或将图标的 `RenderBox.localToGlobal()` 计算位置。

## 计算结果输出

### 非文件模式 / 文件未导入

结果 Card 展示：

```
┌─────────────────────────────────┐
│  计算结果                        │
│                                 │
│  HEX:  0xE8C7                   │
│  Bin:  1110 1000 1100 0111     │
│  Dec:  59591                     │
│                                 │
│  字节长度: 4 bytes               │
└─────────────────────────────────┘
```

### 文件模式（已导入文件）

右侧展示区上下分栏：

```
┌─────────────────────────────────┐
│  文件预览: example.bin           │
│  ┌───────────────────────────┐  │
│  │ Offset   00 01 02 ... 0F  │  │  ← HexAsciiViewer（只读）
│  │ 00000000 31 32 33 34 ...  │  │     约占60%高度
│  │ ...                       │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  计算结果                        │
│  HEX:  0xA1B2C3D4               │
│  Bin:  1010 0001 1011 0010 ...  │
│  Dec:  2712847316                │
│  字节长度: 1024 bytes            │
└─────────────────────────────────┘
```

- 无数据时显示："请输入数据"
- 计算错误时显示红色错误信息
- 结果字体使用等宽字体（monospace）
- `HexAsciiViewer` 传入 `bytes: viewModel.fileBytes`，`onByteChanged: null`（只读）

## 架构设计

### 目录结构

新增 4 个文件，修改 1 个文件：

```
lib/
├── models/toolbox/
│   └── crc_params.dart              # [新增] CRC参数模型 + 21种预设数据 + 数据输入模式枚举
├── services/toolbox/
│   └── crc_calculator.dart          # [新增] CRC核心计算引擎（纯Dart，零Flutter依赖）
├── viewmodels/toolbox/
│   └── crc_viewmodel.dart           # [新增] CRC工具状态管理（ChangeNotifier）
├── views/toolbox/
│   ├── toolbox_tool_registry.dart   # [修改] 注册"CRC计算"工具
│   └── tools/
│       └── crc_tool.dart            # [新增] CRC工具UI页面
```

### 依赖关系

```
crc_tool.dart (View)
  └─ context.watch<CrcViewModel>()
       └─ CrcViewModel (ChangeNotifier)
            └─ CrcCalculator.calculate(bytes, params)  →  int
            └─ CrcPresets.all                           →  List<CrcPreset>
                 └─ CrcParams

crc_calculator.dart (Service)  ← 零 Flutter 依赖
crc_params.dart (Model)        ← 零 Flutter 依赖
```

### 状态管理

延续项目现有 `provider` + `ChangeNotifier` 模式：

```dart
class CrcViewModel extends ChangeNotifier {
  // 数据输入
  DataInputMode _inputMode;
  String _hexText;        // Hex模式文本
  String _asciiText;      // ASCII模式文本
  List<int>? _fileBytes;  // 文件模式字节
  String? _fileName;      // 导入文件名

  // CRC参数
  String? _selectedPreset;  // null = 自定义模式
  CrcParams _customParams;  // 用户自定义的参数值

  // 关于弹窗
  bool _isAboutPinned;
  bool _isAboutHovered;

  // 计算结果
  int? _result;
  String? _error;

  // 每次发生变化时调用 _recalculate()
}
```

### 工具注册

在 `toolbox_tool_registry.dart` 的 `tools` 列表末尾追加：

```dart
ToolboxToolDefinition(
  title: 'CRC计算',
  icon: Icons.calculate_outlined,
  builder: (_) => const CrcTool(),
),
```

## 测试计划

单元测试覆盖：

- CRC-16/MODBUS 对已知数据的计算结果（如 `[0x31, 0x32, 0x33, 0x34]`）。
- CRC-32 对已知数据的计算结果（如 `"123456789"` → `0xCBF43926`）。
- CRC-8 对单字节数据的计算结果。
- 21 种预设模型各至少一条验证用例。
- REFIN=true/false 的正确性。
- REFOUT=true/false 的正确性。
- 空数据输入的行为。
- Hex 文本解析：正常输入、含空格、含非法字符。
- 自定义参数边界（WIDTH=1, WIDTH=32）。
- 结果格式化：Hex/Bin/Dec 三种输出。

Widget 测试：

- 三种输入模式 Tab 切换正常。
- 预设模型下拉选择后结果更新。
- "关于"图标悬浮弹出/消失。
- "关于"图标点击常驻/关闭。

验证命令：

- `flutter test`
- `flutter analyze`

## 风险与处理

- CRC 算法正确性：21 种预设各需验证，以参考网站的在线计算结果作为标准答案进行交叉验证。
- 大文件计算性能：逐位算法对文件模式可能较慢。首版使用逐位算法（最多32位宽，复杂度 O(n×8)），后续可优化为查表法。
- Overlay 定位：悬浮弹窗需正确计算位置，处理边界溢出（弹窗超出屏幕时向上翻转）。
