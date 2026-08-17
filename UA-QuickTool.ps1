# ============================================================
#  Understand Anything 快速工具 v1.1
#  PowerShell 实现（替代原 .bat 版本）
#  - 解决中文 .bat 在 VS Code / cmd 下的编码兼容问题
#  - 功能与原 .bat 一致：安装、卸载、构建、Dashboard、状态
#  - 动态统计 skills/agents 数量，不再硬编码
# ============================================================

$Script:Version = "v1.1"

# ------------------------------------------------------------
# 路径智能检测
# ------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$Script:UADir = $null
if (Test-Path (Join-Path $ScriptDir "understand-anything-plugin\package.json")) {
    $Script:UADir = $ScriptDir
} elseif (Test-Path (Join-Path $ScriptDir "..\understand-anything-plugin\package.json")) {
    $Script:UADir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
}

if (-not $Script:UADir) {
    Write-Host "[错误] 未找到 Understand Anything 源码！" -ForegroundColor Red
    Write-Host "请将此脚本放在 Understand Anything 仓库根目录下。" -ForegroundColor Red
    Read-Host "按任意键退出"
    exit 1
}

# ------------------------------------------------------------
# 检查 pnpm
# ------------------------------------------------------------
# 优先 .CMD 版本：PowerShell 执行策略会阻止 .ps1 脚本
$Script:PnpmCmd = Get-Command pnpm.CMD -ErrorAction SilentlyContinue
if (-not $Script:PnpmCmd) { $Script:PnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue }
if (-not $Script:PnpmCmd) {
    Write-Host "检测到 pnpm 未安装，正在通过 npm 自动安装..." -ForegroundColor Yellow
    npm i -g pnpm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] pnpm 安装失败，请手动执行: npm i -g pnpm" -ForegroundColor Red
        Read-Host "按任意键退出"
        exit 1
    }
    Write-Host "pnpm 安装成功!"
    $Script:PnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------
# 状态检测
# ------------------------------------------------------------
$Script:Built = $false
$Script:DepsInstalled = $false
if (Test-Path (Join-Path $Script:UADir "node_modules\.pnpm")) { $Script:DepsInstalled = $true }
if (Test-Path (Join-Path $Script:UADir "understand-anything-plugin\packages\core\dist")) { $Script:Built = $true }
if (Test-Path (Join-Path $Script:UADir "understand-anything-plugin\packages\dashboard\dist")) { $Script:Built = $true }

$Script:CopilotSkills = Join-Path $env:USERPROFILE ".copilot\skills"
$Script:CopilotAgents = Join-Path $env:USERPROFILE ".copilot\agents"
$Script:UAPluginLink  = Join-Path $env:USERPROFILE ".understand-anything-plugin"

$Script:Installed = Test-Path (Join-Path $Script:CopilotSkills "understand\SKILL.md")

# ------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------
function Show-ToolBanner {
    Write-Host "================================================"
    Write-Host "  Understand Anything 快速工具 $Script:Version"
    Write-Host "  交互式代码知识图谱 --- 一键安装管理"
    Write-Host "================================================"
}

function Invoke-Pnpm {
    # 调用 pnpm 并返回退出码（.ps1 会被执行策略阻止，改用 .CMD）
    param([string[]]$PnpmArgs)
    $exe = $Script:PnpmCmd.Source
    if ($Script:PnpmCmd.Name -like "*.ps1") {
        $alt = [IO.Path]::ChangeExtension($exe, ".CMD")
        if (Test-Path $alt) { $exe = $alt }
    }
    & $exe @PnpmArgs | Out-Host
    return $LASTEXITCODE
}

function New-JunctionSafe {
    # 创建 junction，若目标已存在则跳过
    param([string]$LinkPath, [string]$TargetPath)
    if (Test-Path $LinkPath) {
        Write-Host "  - $([IO.Path]::GetFileName($LinkPath)) 已存在，跳过"
        return
    }
    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $LinkPath) {
        Write-Host "  + $([IO.Path]::GetFileName($LinkPath))"
    } else {
        Write-Host "  ! $([IO.Path]::GetFileName($LinkPath)) 创建失败(可能需要管理员权限)" -ForegroundColor Yellow
    }
}

function Remove-JunctionSafe {
    # 仅删除 junction/符号链接，绝不删除真实目录内容
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink')) {
        try {
            $item.Delete()
            return $true
        } catch {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            return -not (Test-Path $Path)
        }
    }
    return $false
}

function New-HardLinkSafe {
    # 创建文件硬链接（junction 不能指向文件，agent .md 用硬链接）
    param([string]$LinkPath, [string]$TargetPath)
    if (Test-Path $LinkPath) {
        Write-Host "  - $([IO.Path]::GetFileName($LinkPath)) 已存在，跳过"
        return
    }
    New-Item -ItemType HardLink -Path $LinkPath -Target $TargetPath -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $LinkPath) {
        Write-Host "  + $([IO.Path]::GetFileName($LinkPath))"
    } else {
        Write-Host "  ! $([IO.Path]::GetFileName($LinkPath)) 创建失败" -ForegroundColor Yellow
    }
}

function Get-SkillCount {
    $dir = Join-Path $Script:UADir "understand-anything-plugin\skills"
    if (Test-Path $dir) { return (Get-ChildItem $dir -Directory).Count }
    return 0
}

function Get-AgentCount {
    $dir = Join-Path $Script:UADir "understand-anything-plugin\agents"
    if (Test-Path $dir) { return (Get-ChildItem $dir -Filter "*.md" -File).Count }
    return 0
}

# ------------------------------------------------------------
# 安装依赖
# ------------------------------------------------------------
function Install-Deps {
    Clear-Host
    Write-Host "================================================"
    Write-Host "              安装依赖"
    Write-Host "================================================"
    Write-Host ""
    Push-Location $Script:UADir
    $code = Invoke-Pnpm "install"
    Pop-Location
    if ($code -ne 0) {
        Write-Host ""
        Write-Host "[错误] 依赖安装失败！" -ForegroundColor Red
    } else {
        $Script:DepsInstalled = $true
        Write-Host ""
        Write-Host "依赖安装完成!"
    }
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 构建项目
# ------------------------------------------------------------
function Build-Project {
    Clear-Host
    Write-Host "================================================"
    Write-Host "              构建项目"
    Write-Host "================================================"
    Write-Host ""
    Push-Location $Script:UADir
    $code = Invoke-Pnpm "run" "build"
    Pop-Location
    if ($code -ne 0) {
        Write-Host ""
        Write-Host "[错误] 构建失败！" -ForegroundColor Red
    } else {
        $Script:Built = $true
        Write-Host ""
        Write-Host "构建成功!"
    }
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 安装到 VS Code Copilot
# ------------------------------------------------------------
function Install-ToCopilot {
    Clear-Host
    Write-Host "================================================"
    Write-Host "          安装到 VS Code Copilot"
    Write-Host "================================================"
    Write-Host ""

    # 创建目标目录
    New-Item -ItemType Directory -Path $Script:CopilotSkills -Force | Out-Null
    New-Item -ItemType Directory -Path $Script:CopilotAgents -Force | Out-Null

    # 链接 Skills
    Write-Host "--- 链接 Skills ---"
    $skillsRoot = Join-Path $Script:UADir "understand-anything-plugin\skills"
    if (Test-Path $skillsRoot) {
        Get-ChildItem $skillsRoot -Directory | ForEach-Object {
            New-JunctionSafe -LinkPath (Join-Path $Script:CopilotSkills $_.Name) -TargetPath $_.FullName
        }
    }

    # 链接 Agents（文件用硬链接，junction 只能指向目录）
    Write-Host ""
    Write-Host "--- 链接 Agents ---"
    $agentsRoot = Join-Path $Script:UADir "understand-anything-plugin\agents"
    if (Test-Path $agentsRoot) {
        Get-ChildItem $agentsRoot -Filter "*.md" -File | ForEach-Object {
            New-HardLinkSafe -LinkPath (Join-Path $Script:CopilotAgents $_.Name) -TargetPath $_.FullName
        }
    }

    # 通用插件根目录链接
    Write-Host ""
    Write-Host "--- 通用插件根目录 ---"
    New-JunctionSafe -LinkPath $Script:UAPluginLink -TargetPath (Join-Path $Script:UADir "understand-anything-plugin")

    $Script:Installed = $true
    Write-Host ""
    Write-Host "安装完成！请重启 VS Code 使配置生效。" -ForegroundColor Green
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 一键安装
# ------------------------------------------------------------
function Install-All {
    Clear-Host
    Write-Host "================================================"
    Write-Host "              一键安装"
    Write-Host "================================================"
    Write-Host ""

    Write-Host "--- 步骤1/3: 安装依赖 ---"
    Push-Location $Script:UADir
    $code = Invoke-Pnpm "install"
    Pop-Location
    if ($code -ne 0) {
        Write-Host ""
        Write-Host "[错误] 依赖安装失败！" -ForegroundColor Red
        Read-Host "按任意键返回主菜单"
        return
    }
    $Script:DepsInstalled = $true
    Write-Host "依赖安装完成!"
    Write-Host ""

    Write-Host "--- 步骤2/3: 构建项目 ---"
    Push-Location $Script:UADir
    $code = Invoke-Pnpm "run" "build"
    Pop-Location
    if ($code -ne 0) {
        Write-Host ""
        Write-Host "[错误] 构建失败！" -ForegroundColor Red
        Read-Host "按任意键返回主菜单"
        return
    }
    $Script:Built = $true
    Write-Host "构建成功!"
    Write-Host ""

    Write-Host "--- 步骤3/3: 安装到 Copilot ---"
    Install-ToCopilot
}

# ------------------------------------------------------------
# 卸载
# ------------------------------------------------------------
function Uninstall-Plugin {
    Clear-Host
    Write-Host "================================================"
    Write-Host "           从 Copilot 卸载"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "即将移除以下内容:"
    Write-Host "  - Copilot Skills 中的 UA 相关链接"
    Write-Host "  - Copilot Agents 中的 UA 相关链接"
    Write-Host "  - 通用插件根目录 $Script:UAPluginLink"
    Write-Host ""
    $confirm = Read-Host "确认卸载? (y/n)"
    if ($confirm -notmatch "^[yY]") { 
        Write-Host ""
        Write-Host "------------------------------------------------"
        Read-Host "按任意键返回主菜单"
        return 
    }

    # 移除 Skills 链接
    Write-Host ""
    Write-Host "--- 移除 Skills ---"
    $skillsRoot = Join-Path $Script:UADir "understand-anything-plugin\skills"
    if ((Test-Path $skillsRoot) -and (Test-Path $Script:CopilotSkills)) {
        Get-ChildItem $skillsRoot -Directory | ForEach-Object {
            $link = Join-Path $Script:CopilotSkills $_.Name
            if (Remove-JunctionSafe -Path $link) {
                Write-Host "  - 移除 $($_.Name)"
            }
        }
    }

    # 移除 Agents 链接（硬链接直接用 Remove-Item，不影响仓库原文件）
    Write-Host ""
    Write-Host "--- 移除 Agents ---"
    $agentsRoot = Join-Path $Script:UADir "understand-anything-plugin\agents"
    if ((Test-Path $agentsRoot) -and (Test-Path $Script:CopilotAgents)) {
        Get-ChildItem $agentsRoot -Filter "*.md" -File | ForEach-Object {
            $link = Join-Path $Script:CopilotAgents $_.Name
            if (Test-Path $link) {
                Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $link)) {
                    Write-Host "  - 移除 $($_.Name)"
                }
            }
        }
    }

    # 移除通用插件根目录链接
    Write-Host ""
    Write-Host "--- 通用插件根目录 ---"
    if (Remove-JunctionSafe -Path $Script:UAPluginLink) {
        Write-Host "  - 已移除"
    }

    $Script:Installed = $false
    Write-Host ""
    Write-Host "卸载完成!"
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 启动 Dashboard
# ------------------------------------------------------------
function Start-Dashboard {
    Clear-Host
    Write-Host "================================================"
    Write-Host "          启动 Dashboard"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "正在启动 Dashboard 开发服务器..."
    Write-Host "浏览器将打开 http://localhost:5173"
    Write-Host "按 Ctrl+C 停止服务"
    Write-Host ""
    Push-Location $Script:UADir
    Invoke-Pnpm "dev:dashboard"
    Pop-Location
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 安装状态
# ------------------------------------------------------------
function Show-Status {
    Clear-Host
    Write-Host "================================================"
    Write-Host "              安装状态"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "--- 环境 ---"
    $nodeVer = node --version 2>$null
    Write-Host "  Node.js: $nodeVer"
    if ($Script:PnpmCmd) {
        $exe = $Script:PnpmCmd.Source
        if ($Script:PnpmCmd.Name -like "*.ps1") {
            $alt = [IO.Path]::ChangeExtension($exe, ".CMD")
            if (Test-Path $alt) { $exe = $alt }
        }
        $pnpmVer = & $exe --version 2>$null
        Write-Host "  pnpm:    v$pnpmVer"
    }
    Write-Host ""
    Write-Host "--- 依赖 ---"
    if ($Script:DepsInstalled) {
        Write-Host "  依赖: 已安装 [OK]"
    } else {
        Write-Host "  依赖: 未安装 [X]" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "--- 构建 ---"
    if ($Script:Built) {
        Write-Host "  构建: 已完成 [OK]"
    } else {
        Write-Host "  构建: 未构建 [X]" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "--- Copilot 插件 ---"
    if ($Script:Installed) {
        Write-Host "  状态: 已安装 [OK]"
        Write-Host "  Skills: $Script:CopilotSkills"
        Write-Host "  Agents: $Script:CopilotAgents"
    } else {
        Write-Host "  状态: 未安装 [X]" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "--- 项目 ---"
    Write-Host "  UA 目录: $Script:UADir"
    Write-Host "  Skills数: $(Get-SkillCount)"
    Write-Host "  Agents数: $(Get-AgentCount)"
    Write-Host ""
    Write-Host "------------------------------------------------"
    Read-Host "按任意键返回主菜单"
}

# ------------------------------------------------------------
# 主菜单
# ------------------------------------------------------------
function Show-Menu {
    Show-ToolBanner
    Write-Host ""
    Write-Host " UA目录: $Script:UADir"
    if ($Script:Installed) { Write-Host " Copilot: [已安装]" } else { Write-Host " Copilot: [未安装]" }
    Write-Host ""
    Write-Host " --- 安装配置 ---"
    Write-Host " [1] 一键安装       pnpm install + 构建 + 安装到Copilot"
    Write-Host " [2] 卸载插件       从Copilot移除"
    Write-Host ""
    Write-Host " --- 启动查看 ---"
    Write-Host " [3] 启动Dashboard  打开可视化面板"
    Write-Host " [4] 安装状态       检查各组件状态"
    Write-Host ""
    Write-Host " --- 维护 ---"
    Write-Host " [5] 仅构建项目"
    Write-Host " [6] 仅安装依赖"
    Write-Host ""
    Write-Host " -----------------------------------------------"
    Write-Host "  [0] 退出"
    Write-Host ""
}

# ------------------------------------------------------------
# 拖放支持（通过 .bat 启动器传入参数）
# ------------------------------------------------------------
$dragTarget = $args[0]
if ($dragTarget) {
    if ([IO.Path]::GetExtension($dragTarget) -eq ".lnk") {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $resolved = $shell.CreateShortcut($dragTarget).TargetPath
            if ($resolved) { $dragTarget = $resolved }
        } catch { }
    }
    if (Test-Path $dragTarget -PathType Container) {
        Push-Location $dragTarget
        Clear-Host
        Show-ToolBanner
        Write-Host ""
        Write-Host " 拖入目标: $dragTarget"
        Write-Host " 已切换到: $(Get-Location)"
        Write-Host ""
        Read-Host "按任意键进入主菜单"
    }
}

# ------------------------------------------------------------
# 主循环
# ------------------------------------------------------------
while ($true) {
    Clear-Host
    Show-Menu
    $choice = Read-Host "请输入选项 (0-6)"
    switch ($choice) {
        "1" { Install-All }
        "2" { Uninstall-Plugin }
        "3" { Start-Dashboard }
        "4" { Show-Status }
        "5" { Build-Project }
        "6" { Install-Deps }
        "0" { exit 0 }
    }
}
