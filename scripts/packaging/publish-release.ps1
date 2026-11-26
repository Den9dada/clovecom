#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [string]$PagesBranch = 'gh-pages'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw '无效的仓库名称。' }
if ($Tag -notmatch '^v\d+\.\d+\.\d+\+\d+$') { throw '无效的发布标签。' }
if ($PagesBranch -notmatch '^[A-Za-z0-9_.-]+$') { throw '无效的 Pages 分支。' }
$directory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('clovecom-publish-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
function Invoke-Gh([string[]]$Arguments) {
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub 操作失败：$($Arguments[0])" }
    return $result
}
function Invoke-Api([string]$Endpoint, [string]$Method = 'GET', $Body = $null) {
    $arguments = @('api', $Endpoint, '--method', $Method)
    if ($null -ne $Body) {
        $bodyFile = Join-Path $work 'request.json'
        [IO.File]::WriteAllText($bodyFile, ($Body | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        $arguments += @('--input', $bodyFile)
    }
    (Invoke-Gh $arguments) | ConvertFrom-Json
}
function Try-GetRef([string]$Endpoint) {
    $result = & gh api $Endpoint 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $result | ConvertFrom-Json
}
try {
    $repo = Invoke-Api "repos/$Repository"
    if ($repo.private) { throw '发布仓库必须公开，用户更新时不能依赖 GitHub 登录。' }
    $ref = Try-GetRef "repos/$Repository/git/ref/heads/$PagesBranch"
    $baseCommit = $null
    $tree = $null
    if ($null -ne $ref) {
        $baseCommit = Invoke-Api "repos/$Repository/git/commits/$($ref.object.sha)"
        $tree = Invoke-Api "repos/$Repository/git/trees/$($baseCommit.tree.sha)"
        $currentFeed = @($tree.tree | Where-Object path -EQ 'CloveCOM.appinstaller')
        if ($currentFeed.Count) {
            $blob = Invoke-Api "repos/$Repository/git/blobs/$($currentFeed[0].sha)"
            [xml]$previous = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob.content))
            [xml]$next = Get-Content -LiteralPath (Join-Path $directory 'CloveCOM.appinstaller') -Raw
            if ($previous.AppInstaller.MainPackage.Name -ne $next.AppInstaller.MainPackage.Name -or
                $previous.AppInstaller.MainPackage.Publisher -ne $next.AppInstaller.MainPackage.Publisher) {
                throw '发布者或包身份与现有更新清单不同，拒绝切换用户的更新身份。'
            }
            if ([version]$previous.AppInstaller.Version -gt [version]$next.AppInstaller.Version) {
                throw '线上版本较新，拒绝将更新清单回退。'
            }
        }
    }
    # 不覆盖已经公开的安装包；工作流重跑时复用首次发布的清单。
    $encodedTag = [Uri]::EscapeDataString($Tag)
    $releases = @(Invoke-Api "repos/$Repository/releases?per_page=100")
    $existing = @($releases | Where-Object tag_name -EQ $Tag)
    if ($existing.Count -and -not $existing[0].draft) {
        Invoke-Gh @('release', 'download', $Tag, '--repo', $Repository, '--pattern', 'CloveCOM.appinstaller', '--dir', $work) | Out-Null
        [xml]$published = Get-Content -LiteralPath (Join-Path $work 'CloveCOM.appinstaller') -Raw
        [xml]$requested = Get-Content -LiteralPath (Join-Path $directory 'CloveCOM.appinstaller') -Raw
        if ($published.AppInstaller.MainPackage.OuterXml -ne $requested.AppInstaller.MainPackage.OuterXml) {
            throw '同名发行版的包身份或下载地址不同，拒绝重写更新清单。'
        }
        $feedDirectory = $work
    } else {
        if (-not $existing.Count) {
            $notes = Join-Path $work 'notes.md'
            [IO.File]::WriteAllText($notes, "Windows x64。推荐下载 *-setup.exe；ZIP 完整解压后运行 clovecom.exe。MSIX 使用 CloveCOM.appinstaller 安装，使用自签证书时须先信任 CloveCOM-signing.cer。校验值见 SHA256SUMS.txt。更新前请保存工作并退出应用。", [Text.UTF8Encoding]::new($false))
            Invoke-Gh @('release', 'create', $Tag, '--repo', $Repository, '--title', "CloveCOM $Tag", '--notes-file', $notes, '--draft') | Out-Null
        }
        $assets = @(Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Extension -ne '.html' -and $_.Name -notlike '*-SHA256SUMS.txt' } | ForEach-Object FullName)
        Invoke-Gh (@('release', 'upload', $Tag, '--repo', $Repository, '--clobber') + $assets) | Out-Null
        Invoke-Gh @('release', 'edit', $Tag, '--repo', $Repository, '--draft=false', '--latest') | Out-Null
        $feedDirectory = $directory
    }
    # Release 已公开后，原子更新独立 Pages 分支，仅托管更新清单，不污染源码主分支。
    $entries = @(
        @{ path = 'CloveCOM.appinstaller'; mode = '100644'; type = 'blob'; content = [IO.File]::ReadAllText((Join-Path $feedDirectory 'CloveCOM.appinstaller')) }
    )
    if ($null -ne $ref) {
        $newTree = Invoke-Api "repos/$Repository/git/trees" 'POST' @{ base_tree = $baseCommit.tree.sha; tree = $entries }
        $commit = Invoke-Api "repos/$Repository/git/commits" 'POST' @{
            message = "发布 CloveCOM $Tag 更新清单"; tree = $newTree.sha; parents = @($ref.object.sha)
        }
        Invoke-Api "repos/$Repository/git/refs/heads/$PagesBranch" 'PATCH' @{ sha = $commit.sha; force = $false } | Out-Null
    } else {
        $newTree = Invoke-Api "repos/$Repository/git/trees" 'POST' @{ tree = $entries }
        $commit = Invoke-Api "repos/$Repository/git/commits" 'POST' @{
            message = "初始化 CloveCOM $Tag 更新清单"; tree = $newTree.sha; parents = @()
        }
        Invoke-Api "repos/$Repository/git/refs" 'POST' @{ ref = "refs/heads/$PagesBranch"; sha = $commit.sha } | Out-Null
    }
    Write-Output "已发布：https://github.com/$Repository/releases/tag/$encodedTag"
} finally {
    # 此目录由本脚本创建，核对绝对路径后仅清理本次临时文件。
    $absoluteWork = [IO.Path]::GetFullPath($work)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($absoluteWork.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($absoluteWork).StartsWith('clovecom-publish-')) {
        Remove-Item -LiteralPath $absoluteWork -Recurse -Force
    }
}
