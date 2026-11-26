#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ExePath,
    [string]$IconPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $ExePath) { $ExePath = Join-Path $root 'build\windows\x64\runner\Release\clovecom.exe' }
if (-not $IconPath) { $IconPath = Join-Path $root 'windows\runner\resources\app_icon.ico' }

# 直接读取 PE 资源，不启动应用，也不通过 Windows 的图标缓存取图。
if (-not ('CloveCOM.Packaging.IconResources' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace CloveCOM.Packaging {
    public static class IconResources {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr LoadLibraryExW(string file, IntPtr reserved, uint flags);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr resource);
        public static byte[] Read(IntPtr module, int type, int id) {
            IntPtr resource = FindResourceW(module, new IntPtr(id), new IntPtr(type));
            if (resource == IntPtr.Zero) throw new Win32Exception();
            uint size = SizeofResource(module, resource);
            IntPtr data = LockResource(LoadResource(module, resource));
            if (data == IntPtr.Zero || size == 0) throw new Win32Exception();
            byte[] bytes = new byte[checked((int)size)];
            Marshal.Copy(data, bytes, 0, bytes.Length);
            return bytes;
        }
    }
}
'@
}
$icon = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $IconPath).Path)
$module = [CloveCOM.Packaging.IconResources]::LoadLibraryExW(
    (Resolve-Path -LiteralPath $ExePath).Path, [IntPtr]::Zero, 0x22)
if ($module -eq [IntPtr]::Zero) { throw '无法读取 EXE 资源。' }
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $group = [CloveCOM.Packaging.IconResources]::Read($module, 14, 101)
    $count = [BitConverter]::ToUInt16($icon, 4)
    if ([BitConverter]::ToUInt16($group, 4) -ne $count) {
        throw 'EXE 内嵌图标的尺寸数量与当前 ICO 不一致，请重新编译 Windows 资源。'
    }
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + $i * 16
        $length = [BitConverter]::ToUInt32($icon, $entry + 8)
        $offset = [BitConverter]::ToUInt32($icon, $entry + 12)
        $id = [BitConverter]::ToUInt16($group, 6 + $i * 14 + 12)
        $actual = [CloveCOM.Packaging.IconResources]::Read($module, 3, $id)
        $expectedHash = [BitConverter]::ToString($sha.ComputeHash($icon, $offset, $length))
        $actualHash = [BitConverter]::ToString($sha.ComputeHash($actual))
        if ($actualHash -ne $expectedHash) {
            $size = if ($icon[$entry] -eq 0) { 256 } else { $icon[$entry] }
            throw "EXE 内嵌的 ${size}px 图标未更新，拒绝打包旧图标；请重新编译 Windows 资源。"
        }
    }
} finally {
    $sha.Dispose()
    [void][CloveCOM.Packaging.IconResources]::FreeLibrary($module)
}
