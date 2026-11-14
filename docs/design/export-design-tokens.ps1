# 从当前 Flutter 主题导出可跨技术栈使用的设计令牌。
# 不导出业务组件代码；输出为本脚本同目录下的 JSON 与 CSS。
$ErrorActionPreference = 'Stop'
$themePath = Join-Path $PSScriptRoot '../../lib/ui/theme/traework_theme.dart'
$layoutPath = Join-Path $PSScriptRoot '../../lib/ui/layout/responsive.dart'
$themeSource = Get-Content -LiteralPath $themePath -Raw -Encoding utf8
$layoutSource = Get-Content -LiteralPath $layoutPath -Raw -Encoding utf8

function Get-NumericTokens([string]$className) {
    $classPattern = '(?s)class ' + [regex]::Escape($className) + '\s*\{(.*?)\n\}'
    $classBody = [regex]::Match($themeSource, $classPattern).Groups[1].Value
    if (!$classBody) { throw "找不到令牌类 $className" }
    $values = [ordered]@{}
    foreach ($match in [regex]::Matches($classBody, 'static const double (\w+) = ([\d.]+);')) {
        $values[$match.Groups[1].Value] = [double]::Parse($match.Groups[2].Value, [cultureinfo]::InvariantCulture)
    }
    return $values
}

function Convert-Kebab([string]$value) {
    return ([regex]::Replace($value, '([a-z0-9])([A-Z])', '$1-$2')).ToLowerInvariant()
}

$colors = [ordered]@{}
$colorBody = [regex]::Match($themeSource, '(?s)class TraeWorkColors\s*\{(.*?)\n\}').Groups[1].Value
foreach ($match in [regex]::Matches($colorBody, '(?s)static const Color (\w+) = Color\(\s*0x([0-9A-Fa-f]{8}),?\s*\);')) {
    $name = $match.Groups[1].Value
    $argb = $match.Groups[2].Value.ToUpperInvariant()
    $rgb = $argb.Substring(2, 6)
    $alpha = $argb.Substring(0, 2)
    $colors[$name] = [ordered]@{
        flutterArgb = "0x$argb"
        css = if ($alpha -eq 'FF') { "#$rgb" } else { "#$rgb$alpha" }
        opacity = [math]::Round([Convert]::ToInt32($alpha, 16) / 255, 6)
    }
}
if ($colors.Count -lt 40) { throw '颜色导出数量异常，请检查主题格式变化。' }

$spacing = Get-NumericTokens 'TraeWorkSpacers'
$radius = Get-NumericTokens 'TraeWorkRadius'
$fontSizes = Get-NumericTokens 'TraeWorkFontSizes'
$window = [ordered]@{}
foreach ($name in @('minimumLogicalWidth', 'minimumLogicalHeight', 'minContentWidth', 'navWidth', 'navRailWidth')) {
    $value = [regex]::Match($layoutSource, 'static const double ' + $name + ' = ([\d.]+);').Groups[1].Value
    if (!$value) { throw "找不到窗口尺寸 $name" }
    $window[$name] = [double]::Parse($value, [cultureinfo]::InvariantCulture)
}
$preferred = [regex]::Match($layoutSource, 'preferredSize = Size\(([\d.]+), ([\d.]+)\)')
if (!$preferred.Success) { throw '找不到默认窗口尺寸。' }
$window['preferredWidth'] = [double]::Parse($preferred.Groups[1].Value, [cultureinfo]::InvariantCulture)
$window['preferredHeight'] = [double]::Parse($preferred.Groups[2].Value, [cultureinfo]::InvariantCulture)

# 字体、组件规格和密度判断是人工核对快照；修改相关组件时需同步本节。
$snapshot = [ordered]@{
    metadata = [ordered]@{
        project = 'CloveRTLS'
        reviewedOn = '2026-10-15'
        theme = 'light'
        sizeUnit = 'Flutter logical pixel; CSS export uses px'
        source = 'lib/ui/theme/traework_theme.dart'
        note = '颜色及尺寸类自动提取；字体、组件及断点为人工核对快照。'
    }
    colors = $colors
    spacing = $spacing
    radius = $radius
    fontSizes = $fontSizes
    font = [ordered]@{
        ui = @('MiSans', 'Microsoft YaHei', 'Segoe UI')
        mono = @('Consolas', 'Menlo', 'Courier New', 'Microsoft YaHei')
        bundledWeights = @(400, 500, 600, 700)
        note = '参考包不含字体文件；Flutter 未统一固定行高。'
    }
    components = [ordered]@{
        button = [ordered]@{ height = 28; compactHeight = 24; radius = 6; fontSize = 12; compactFontSize = 11; iconSize = 14; gap = 6; paddingX = 12; compactPaddingX = 8 }
        input = [ordered]@{ minHeight = 28; defaultMaxWidth = 240; fontSize = 14; radius = 6; focusBorderWidth = 1.5 }
        select = [ordered]@{ height = 28; defaultMaxWidth = 160; fontSize = 14; radius = 6 }
        card = [ordered]@{ radius = 8; padding = 12; borderWidth = 1 }
        dialog = [ordered]@{ radius = 12; inset = 24; titleFontSize = 16; titleWeight = 600 }
        tag = [ordered]@{ radius = 4; fontSize = 10; fontWeight = 500; paddingX = 6; paddingY = 2 }
        switch = [ordered]@{ width = 36; height = 20; thumbSize = 16; durationMs = 120 }
        toast = [ordered]@{ radius = 8; maxWidth = 360; edgeInset = 16; gap = 8; lifetimeMs = 3000; fadeMs = 180; maxVisible = 4; progressHeight = 3 }
        tagTable = [ordered]@{ headerHeight = 36; rowHeight = 36; minSharedColumnWidth = 64 }
    }
    window = $window
    density = [ordered]@{
        compact = 'width < 1280 OR height < 720; checked first'
        expanded = 'not compact AND width >= 1600'
        regular = 'otherwise'
    }
    interaction = [ordered]@{
        precedence = @('disabled', 'pressed', 'hovered')
        independent = @('focused', 'selected')
        note = '共享品牌按钮禁用使用灰底；danger+selected 仍保留红字。'
    }
}
$snapshot | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'design-tokens.json') -Encoding utf8

$css = [System.Collections.Generic.List[string]]::new()
$css.Add('/* CloveRTLS 浅色 GUI 令牌快照；颜色从 Flutter ARGB 转为 CSS RGBA。 */')
$css.Add('/* 变量不实现控件行为；字体文件需由目标项目配置，组件规格见 gui-style-reference.md。 */')
$css.Add(':root {')
foreach ($name in $colors.Keys) { $css.Add("  --color-$(Convert-Kebab $name): $($colors[$name].css);") }
foreach ($name in $spacing.Keys) { $css.Add("  --space-$($name.Substring(1)): $($spacing[$name])px;") }
foreach ($name in $radius.Keys) {
    $suffix = if ($name -eq 'full') { 'full' } else { $name.Substring(1) }
    $css.Add("  --radius-${suffix}: $($radius[$name])px;")
}
foreach ($name in $fontSizes.Keys) { $css.Add("  --font-size-$(Convert-Kebab $name): $($fontSizes[$name])px;") }
$css.Add('  --font-ui: "MiSans", "Microsoft YaHei", "Segoe UI", sans-serif;')
$css.Add('  --font-mono: "Consolas", "Menlo", "Courier New", "Microsoft YaHei", monospace;')
foreach ($name in $window.Keys) { $css.Add("  --window-$(Convert-Kebab $name): $($window[$name])px;") }
$css.Add('  --control-height: 28px;')
$css.Add('  --control-height-compact: 24px;')
$css.Add('  --border-width: 1px;')
$css.Add('  --focus-border-width: 1.5px;')
$css.Add('  --shadow-map-panel: 0 6px 16px #00000026;')
$css.Add('  --shadow-toast: 0 2px 8px #00000022;')
$css.Add('}')
$css | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'design-tokens.css') -Encoding utf8
Write-Output "已导出 $($colors.Count) 个颜色及间距、圆角、字号、窗口和组件规格。"
