@echo off
chcp 65001 >nul 2>&1
title Understand Anything 快速工具 v1.0
color 0B
setlocal enabledelayedexpansion
@echo off

:: ============================================
:: 路径智能检测
:: ============================================
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 确定 UA 源码根目录
set "UA_DIR="
if exist "%SCRIPT_DIR%\understand-anything-plugin\package.json" set "UA_DIR=%SCRIPT_DIR%"
if exist "%SCRIPT_DIR%\..\understand-anything-plugin\package.json" set "UA_DIR=%SCRIPT_DIR%\.."

if not defined UA_DIR (
    echo([错误] 未找到 Understand Anything 源码！
    echo(请将此脚本放在 Understand Anything 仓库根目录下。
    pause
    exit /b 1
)

:: ============================================
:: 检查 pnpm
:: ============================================
set "PNPM_CMD=pnpm"
where pnpm 2>nul >nul
if errorlevel 1 (
    echo(检测到 pnpm 未安装，正在通过 npm 自动安装...
    call npm i -g pnpm 2>&1
    if errorlevel 1 (
        echo([错误] pnpm 安装失败，请手动执行: npm i -g pnpm
        pause
        exit /b 1
    )
    echo(pnpm 安装成功!
    echo.
)

:: ============================================
:: 检查构建产物 + 依赖
:: ============================================
set "BUILT="
set "DEPS_INSTALLED="
if exist "!UA_DIR!\node_modules\.pnpm\" set "DEPS_INSTALLED=1"
if exist "!UA_DIR!\understand-anything-plugin\packages\core\dist\" set "BUILT=1"
if exist "!UA_DIR!\understand-anything-plugin\packages\dashboard\dist\" set "BUILT=1"

:: ============================================
:: 检查 Copilot 安装状态
:: ============================================
set "COPILOT_SKILLS=%USERPROFILE%\.copilot\skills"
set "COPILOT_AGENTS=%USERPROFILE%\.copilot\agents"
set "UA_PLUGIN_LINK=%USERPROFILE%\.understand-anything-plugin"

set "INSTALLED="
if exist "%COPILOT_SKILLS%\understand\SKILL.md" set "INSTALLED=1"

:: ============================================
:: 拖放支持
:: ============================================
if not "%~1"=="" (
    set "TARGET=%~1"
    if /i "%~x1"==".lnk" (
        for /f "delims=" %%t in ('powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%~f1'); Write-Output $s.TargetPath" 2^>nul') do set "TARGET=%%t"
        if "!TARGET!"=="%~f1" (
            echo([错误] 无法解析快捷方式!
            pause
            exit /b 1
        )
    )
    pushd "!TARGET!" 2>nul
    if errorlevel 1 (
        echo([错误] 无法进入目录: !TARGET!
        pause
        exit /b 1
    )
    cls
    echo ================================================
    echo   Understand Anything 快速工具 v1.0
    echo   交互式代码知识图谱 --- 一键安装管理
    echo ================================================
    echo.
    echo  拖入目标: !TARGET!
    echo  已切换到: %CD%
    echo.
    echo  按任意键进入主菜单...
    pause >nul
)

:menu
cls
echo ================================================
echo   Understand Anything 快速工具 v1.0
echo   交互式代码知识图谱 --- 一键安装管理
echo ================================================
echo.
echo( UA目录: !UA_DIR!
if defined INSTALLED echo( Copilot: [已安装]
if not defined INSTALLED echo( Copilot: [未安装]
echo.
echo( --- 安装配置 ---
echo( [1] 一键安装       pnpm install + 构建 + 安装到Copilot
echo( [2] 卸载插件       从Copilot移除
echo.
echo( --- 启动查看 ---
echo( [3] 启动Dashboard  打开可视化面板
echo( [4] 安装状态       检查各组件状态
echo.
echo( --- 维护 ---
echo( [5] 仅构建项目
echo( [6] 仅安装依赖
echo.
echo( -----------------------------------------------
echo(  [0] 退出
echo.
set /p choice="请输入选项 (0-6): "

if "%choice%"=="1" goto install_all
if "%choice%"=="2" goto uninstall
if "%choice%"=="3" goto dashboard
if "%choice%"=="4" goto status
if "%choice%"=="5" goto build
if "%choice%"=="6" goto deps
if "%choice%"=="0" exit /b
goto menu

:: ============================================
:: 安装依赖
:: ============================================
:deps
cls
echo ================================================
echo              安装依赖
echo ================================================
echo.
pushd "!UA_DIR!"
call pnpm install 2>&1
popd
if errorlevel 1 (
    echo.
    echo([错误] 依赖安装失败！
) else (
    echo.
    echo(依赖安装完成!
)
echo.
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu

:: ============================================
:: 构建
:: ============================================
:build
cls
echo ================================================
echo              构建项目
echo ================================================
echo.
pushd "!UA_DIR!"
call pnpm run build 2>&1
popd
if errorlevel 1 (
    echo.
    echo([错误] 构建失败！
) else (
    set "BUILT=1"
    echo.
    echo(构建成功!
)
echo.
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu

:: ============================================
:: 安装到 Copilot
:: ============================================
:install_to_copilot
cls
echo ================================================
echo          安装到 VS Code Copilot
echo ================================================
echo.

:: 创建目标目录
if not exist "%COPILOT_SKILLS%" mkdir "%COPILOT_SKILLS%"
if not exist "%COPILOT_AGENTS%" mkdir "%COPILOT_AGENTS%"

:: 链接 Skills（每个 skill 单独 junction）
echo(--- 链接 Skills ---
for %%d in ("!UA_DIR!\understand-anything-plugin\skills\*") do (
    if exist "%%d" (
        set "SKILL_NAME=%%~nxd"
        if exist "%COPILOT_SKILLS%\!SKILL_NAME!" (
            echo(  • !SKILL_NAME! 已存在，跳过
        ) else (
            mklink /J "%COPILOT_SKILLS%\!SKILL_NAME!" "%%d" >nul 2>&1
            if not errorlevel 1 (
                echo(  ✓ !SKILL_NAME!
            ) else (
                echo(  ✗ !SKILL_NAME! 创建失败(可能需要管理员权限)
            )
        )
    )
)

:: 链接 Agents（每个 agent 单独 junction）
echo.
echo(--- 链接 Agents ---
if not exist "%COPILOT_AGENTS%" mkdir "%COPILOT_AGENTS%"
for %%d in ("!UA_DIR!\understand-anything-plugin\agents\*") do (
    if exist "%%d" (
        set "AGENT_NAME=%%~nxd"
        if exist "%COPILOT_AGENTS%\!AGENT_NAME!" (
            echo(  • !AGENT_NAME! 已存在，跳过
        ) else (
            mklink /J "%COPILOT_AGENTS%\!AGENT_NAME!" "%%d" >nul 2>&1
            if not errorlevel 1 (
                echo(  ✓ !AGENT_NAME!
            ) else (
                echo(  ✗ !AGENT_NAME! 创建失败(可能需要管理员权限)
            )
        )
    )
)

:: 创建通用插件根目录链接
echo.
echo(--- 通用插件根目录 ---
if not exist "%UA_PLUGIN_LINK%" (
    mklink /J "%UA_PLUGIN_LINK%" "!UA_DIR!\understand-anything-plugin" >nul 2>&1
    if not errorlevel 1 (
        echo(  ✓ %UA_PLUGIN_LINK%
    ) else (
        echo(  ✗ 创建失败
    )
) else (
    echo(  • %UA_PLUGIN_LINK% 已存在
)

set "INSTALLED=1"
echo.
echo(安装完成！请重启 VS Code 使配置生效。
echo.
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu

:: ============================================
:: 一键安装
:: ============================================
:install_all
cls
echo ================================================
echo              一键安装
echo ================================================
echo.
echo(--- 步骤1/3: 安装依赖 ---
pushd "!UA_DIR!"
call pnpm install 2>&1
if errorlevel 1 (
    popd
    echo.
    echo([错误] 依赖安装失败！
    pause
    goto menu
)
popd
set "DEPS_INSTALLED=1"
echo(依赖安装完成!
echo.

echo(--- 步骤2/3: 构建项目 ---
pushd "!UA_DIR!"
call pnpm run build 2>&1
if errorlevel 1 (
    popd
    echo.
    echo([错误] 构建失败！
    pause
    goto menu
)
popd
set "BUILT=1"
echo(构建成功!
echo.

echo(--- 步骤3/3: 安装到 Copilot ---
goto :install_to_copilot

:: ============================================
:: 卸载
:: ============================================
:uninstall
cls
echo ================================================
echo           从 Copilot 卸载
echo ================================================
echo.
echo(即将移除以下内容:
echo(  - Copilot Skills 中的 UA 相关链接
echo(  - Copilot Agents 中的 UA 相关链接
echo(  - 通用插件根目录 %UA_PLUGIN_LINK%
echo.
set /p confirm="确认卸载? (y/n): "
if /i not "!confirm!"=="y" goto :uninstall_skip

:: 移除 Skills 链接
echo.
echo(--- 移除 Skills ---
if exist "%COPILOT_SKILLS%" (
    for %%d in ("!UA_DIR!\understand-anything-plugin\skills\*") do (
        if exist "%%d" (
            set "SKILL_NAME=%%~nxd"
            if exist "%COPILOT_SKILLS%\!SKILL_NAME!" (
                fsutil reparsepoint delete "%COPILOT_SKILLS%\!SKILL_NAME!" >nul 2>&1
                if not errorlevel 1 (
                    echo(  ✓ 移除 !SKILL_NAME!
                ) else (
                    rmdir "%COPILOT_SKILLS%\!SKILL_NAME!" >nul 2>&1 && echo(  ✓ 移除 !SKILL_NAME!
                )
            )
        )
    )
)

:: 移除 Agents 链接
echo.
echo(--- 移除 Agents ---
if exist "%COPILOT_AGENTS%" (
    for %%d in ("!UA_DIR!\understand-anything-plugin\agents\*") do (
        if exist "%%d" (
            set "AGENT_NAME=%%~nxd"
            if exist "%COPILOT_AGENTS%\!AGENT_NAME!" (
                fsutil reparsepoint delete "%COPILOT_AGENTS%\!AGENT_NAME!" >nul 2>&1
                if not errorlevel 1 (
                    echo(  ✓ 移除 !AGENT_NAME!
                ) else (
                    rmdir "%COPILOT_AGENTS%\!AGENT_NAME!" >nul 2>&1 && echo(  ✓ 移除 !AGENT_NAME!
                )
            )
        )
    )
)

:: 移除通用插件根目录链接
echo.
echo(--- 通用插件根目录 ---
if exist "%UA_PLUGIN_LINK%" (
    fsutil reparsepoint delete "%UA_PLUGIN_LINK%" >nul 2>&1 || rmdir "%UA_PLUGIN_LINK%" >nul 2>&1
    echo(  ✓ 已移除
)

set "INSTALLED="
echo.
echo(卸载完成!
echo.
:uninstall_skip
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu

:: ============================================
:: Dashboard
:: ============================================
:dashboard
cls
echo ================================================
echo          启动 Dashboard
echo ================================================
echo.
echo(正在启动 Dashboard 开发服务器...
echo(浏览器将打开 http://localhost:5173
echo(按 Ctrl+C 停止服务
echo.
pushd "!UA_DIR!"
pnpm dev:dashboard
popd
echo.
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu

:: ============================================
:: 安装状态
:: ============================================
:status
cls
echo ================================================
echo              安装状态
echo ================================================
echo.
echo(--- 环境 ---
for /f "tokens=1" %%v in ('node --version 2^>nul') do set "NODE_VER=%%v"
echo(  Node.js: !NODE_VER!
for /f "tokens=1" %%v in ('pnpm --version 2^>nul') do set "PNPM_VER=%%v"
if defined PNPM_VER echo(  pnpm:    v!PNPM_VER!
echo.
echo(--- 依赖 ---
if defined DEPS_INSTALLED (
    echo(  依赖: 已安装 ✓
) else (
    echo(  依赖: 未安装 ✗
)
echo.
echo(--- 构建 ---
if defined BUILT (
    echo(  构建: 已完成 ✓
) else (
    echo(  构建: 未构建 ✗
)
echo.
echo(--- Copilot 插件 ---
if defined INSTALLED (
    echo(  状态: 已安装 ✓
    echo(  Skills: %COPILOT_SKILLS%
    echo(  Agents: %COPILOT_AGENTS%
) else (
    echo(  状态: 未安装 ✗
)
echo.
echo(--- 项目 ---
echo(  UA 目录: !UA_DIR!
echo(  Skills数: 8 (understand, chat, dashboard, diff, domain, explain, knowledge, onboard)
echo(  Agents数: 9 (scanner, analyzer, builder, reviewer...)
echo.
echo ------------------------------------------------
echo(按任意键返回主菜单...
pause >nul
goto menu
