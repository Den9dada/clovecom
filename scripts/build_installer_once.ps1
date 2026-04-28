param(
  [switch]$Build
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $repoRoot 'release_package/inno_output/CloveComSetup.exe'

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  Write-Host ""
  Write-Host "==> $Name"
  try {
    & $Action
  } catch {
    Write-Host ""
    Write-Error "步骤失败：$Name"
    throw
  }
}

Write-Host '一键生成 CloveCom 安装向导'
Write-Host "项目目录：$repoRoot"

if ($Build) {
  Invoke-Step '构建 Flutter Windows Release' {
    Push-Location $repoRoot
    try {
      flutter build windows --release
    } finally {
      Pop-Location
    }
  }
} else {
  Write-Host '跳过 Flutter 构建。请确认已手动运行过：flutter build windows --release'
}

Invoke-Step '准备共享发布输入目录' {
  if ($Build) {
    & (Join-Path $PSScriptRoot 'prepare_enigma_release.ps1') -Build
  } else {
    & (Join-Path $PSScriptRoot 'prepare_enigma_release.ps1')
  }
}

Invoke-Step '检查 Windows 原生依赖' {
  & (Join-Path $PSScriptRoot 'check_windows_release_dependencies.ps1')
}

Invoke-Step '检查 Inno Setup 安装包输入' {
  & (Join-Path $PSScriptRoot 'check_inno_setup_release.ps1')
}

Invoke-Step '编译 Inno Setup 安装包' {
  & (Join-Path $PSScriptRoot 'prepare_inno_setup_release.ps1')
}

if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "安装包生成后未找到：$installerPath"
}

Write-Host ""
Write-Host '安装向导生成完成：'
Write-Host $installerPath
Write-Host ""
Write-Host '建议复制到干净的 Windows 10/11 x64 电脑或 Windows Sandbox 中测试安装、启动和卸载。'
