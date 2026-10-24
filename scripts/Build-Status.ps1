[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^Reluctant2828/[A-Za-z0-9_.-]+$')]
    [string]$Repository,
    [switch]$Dispatch,
    [switch]$ConfirmFreeQuota,
    [ValidatePattern('^[A-Za-z0-9_./-]+$')]
    [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw '请先安装 GitHub CLI，并在你自己的终端完成 gh auth login。'
}
$identity = gh api user --jq .login
if ($LASTEXITCODE -ne 0 -or $identity.Trim() -ne 'Reluctant2828') {
    throw '当前 GitHub 账号不是方案指定的 Reluctant2828，已停止。'
}
$raw = gh repo view $Repository --json nameWithOwner,isPrivate,defaultBranchRef
if ($LASTEXITCODE -ne 0) { throw '无法只读检查目标仓库。' }
$repo = $raw | ConvertFrom-Json
if ($repo.nameWithOwner -cne $Repository -or -not $repo.isPrivate) {
    throw '目标必须与参数完全一致，而且必须是私有仓库。'
}

if ($Dispatch) {
    if (-not $ConfirmFreeQuota) {
        throw '启动前请在 GitHub Billing 确认可用免费额度，并将付费预算设为 0，然后添加 -ConfirmFreeQuota。'
    }
    if ($PSCmdlet.ShouldProcess("$Repository ($Ref)", '启动一次最长 20 分钟的云端 iOS 编译')) {
        gh workflow run build-ios.yml --repo $Repository --ref $Ref -f free_quota_confirmed=true
        if ($LASTEXITCODE -ne 0) { throw '构建启动失败。' }
    }
} else {
    Write-Output '只读模式：不会创建仓库、上传源码或启动构建。'
}
gh run list --repo $Repository --workflow build-ios.yml --limit 5 --json databaseId,status,conclusion,createdAt,url
if ($LASTEXITCODE -ne 0) { throw '读取构建状态失败。' }
