@echo off
rem ---------------------------------------------------------------------------
rem  claude-switch - start here (guided entry point for first-time users)
rem
rem  Korean text below is UTF-8. "chcp 65001" must come before any non-ASCII
rem  line, because cmd.exe decodes each line as it executes using the codepage
rem  that is active at that moment.
rem ---------------------------------------------------------------------------
chcp 65001 >nul
setlocal
title claude-switch
cd /d "%~dp0"

echo.
echo  ============================================
echo    claude-switch
echo    Claude Desktop 계정 전환 도구
echo  ============================================
echo.

rem --- Check 1: is this the Microsoft Store build of Claude Desktop? ---
echo  [1/2] Claude Desktop 설치를 확인합니다...
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-AppxPackage -Name Claude) { exit 0 } exit 1"
if errorlevel 1 goto no_claude
echo        확인되었습니다.
echo.

rem --- Check 2: are the tool files still together in one folder? ---
echo  [2/2] 필요한 파일을 확인합니다...
if not exist "%~dp0claude-switch.ps1" goto no_script
echo        확인되었습니다.
echo.

echo  ----------------------------------------------------------
echo   아래 목록에서 사용할 계정의 번호를 입력하고 Enter를 누르세요.
echo.
echo   - 처음 실행하면 지금 로그인된 계정이 자동으로 main 이 됩니다.
echo   - 새 계정을 추가하려면 N 을 누르고 이름을 정해주세요.
echo     예: work, personal  (한글과 공백은 사용할 수 없습니다)
echo   - 계정을 바꾸면 Claude 가 자동으로 다시 열립니다.
echo   - 그냥 나가려면 Q 를 누르세요.
echo  ----------------------------------------------------------

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" -Menu
if errorlevel 1 goto failed

echo.
echo  작업이 끝났습니다. 이 창은 닫아도 됩니다.
echo.
echo  참고: Claude Desktop 을 업데이트하기 전에는 stop.cmd 를 먼저 실행하세요.
echo        그렇게 하지 않으면 업데이트가 실패하고 재부팅이 필요할 수 있습니다.
echo.
pause
exit /b 0

:no_claude
echo.
echo  [!] Microsoft Store 에서 설치한 Claude Desktop 을 찾을 수 없습니다.
echo.
echo      이 도구는 Microsoft Store 버전 Claude Desktop 에서만 동작합니다.
echo      홈페이지에서 내려받아 설치한 버전은 지원하지 않습니다.
echo.
echo      Microsoft Store 를 열어 Claude 를 설치한 뒤,
echo      한 번 로그인하고 나서 이 파일을 다시 실행해 주세요.
echo.
choice /c YN /n /m "  지금 Microsoft Store 를 열까요? [Y=예 / N=아니오]: "
if errorlevel 2 goto end_no_claude
start "" "ms-windows-store://search?query=Claude"

:end_no_claude
echo.
pause
exit /b 1

:no_script
echo.
echo  [!] claude-switch.ps1 파일을 찾을 수 없습니다.
echo.
echo      압축 파일 안에서 바로 실행하면 이런 문제가 생깁니다.
echo      1. 내려받은 zip 파일에서 마우스 오른쪽 클릭
echo      2. "압축 풀기" 를 눌러 폴더로 꺼내기
echo      3. 그 폴더 안의 시작하기.cmd 를 다시 실행
echo.
echo      또한 이 파일은 claude-switch.ps1 과 같은 폴더에 있어야 합니다.
echo.
pause
exit /b 1

:failed
echo.
echo  [!] 작업 중 문제가 발생했습니다. 위에 표시된 메시지를 확인해 주세요.
echo.
echo      Claude 가 완전히 닫히지 않아 실패한 경우가 가장 많습니다.
echo      stop.cmd 를 실행해 Claude 를 완전히 종료한 뒤 다시 시도해 보세요.
echo.
pause
exit /b 1
