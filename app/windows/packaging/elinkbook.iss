; elinkBook Windows 安裝程式（Inno Setup 6）— epic-66 Issue 27
; 由 app/tool/package_windows_installer.ps1 以 iscc /D 傳入下列定義後編譯：
;   AppVersion、VersionInfoVersion、StageDir、OutputDir、OutputBaseFilename
;   AppIdOverride（可選，只給變異驗證用；未給則使用下方固定 AppId）
;   AppDataRootOverride、DocsRootOverride（可選，只給「解除安裝選是」的驗證用，把資料根目錄指到假資料夾；出貨版不帶）

#ifndef AppVersion
  #error 缺少 /DAppVersion
#endif
#ifndef VersionInfoVersion
  #error 缺少 /DVersionInfoVersion
#endif
#ifndef StageDir
  #error 缺少 /DStageDir
#endif
#ifndef OutputDir
  #error 缺少 /DOutputDir
#endif
#ifndef OutputBaseFilename
  #error 缺少 /DOutputBaseFilename
#endif

; 固定 AppId：發佈後不可更改，改了就無法覆蓋升級，只會與舊版並存兩份（ADR 0043）。
; Inno Setup 把「{」當常數起始，所以開頭的花括號要雙寫（{{GUID}）。
#ifdef AppIdOverride
  #define AppIdValue AppIdOverride
#else
  #define AppIdValue "{{C4E48E89-6F1B-4B77-94B9-23BCE3FCC757}"
#endif

[Setup]
AppId={#AppIdValue}
AppName=elinkBook
AppVersion={#AppVersion}
AppPublisher=cc.ugotit
VersionInfoVersion={#VersionInfoVersion}
; 依目前使用者安裝，不需要系統管理員權限
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\elinkBook
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
; 覆蓋升級時若 App 正在執行，提示（靜默模式自動）關閉，不重新啟動
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\elinkbook.exe
Compression=lzma2
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}

[Languages]
Name: "zh_tw"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
; 不加 unchecked 旗標：桌面捷徑預設勾選
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\elinkBook"; Filename: "{app}\elinkbook.exe"
Name: "{autodesktop}\elinkBook"; Filename: "{app}\elinkbook.exe"; Tasks: desktopicon

[Code]
// 尋找視窗，用來判斷 elinkBook 是否正在執行（不能改 windows/runner 加互斥鎖，所以以視窗類別加標題辨識；
// 只比類別會誤擋其他用預設範本建置的 Flutter App）。
function FindWindowW(lpClassName: String; lpWindowName: String): LongInt;
  external 'FindWindowW@user32.dll stdcall';

// 解除安裝程式不會像安裝程式那樣關閉執行中的 App；App 開著時檔案被鎖住刪不掉，
// 卻會把登錄項移除，留下沒有移除入口的殘骸。所以偵測到執行中就中止解除安裝。
function InitializeUninstall(): Boolean;
begin
  Result := True;
  if FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'elinkbook') <> 0 then
  begin
    if not UninstallSilent then
      MsgBox('elinkBook 正在執行，請先關閉後再解除安裝。', mbError, MB_OK);
    Result := False;
  end;
end;

// App 資料分放兩處（見 ADR 0043、ADR 0044）：
//   1. %APPDATA%\cc.ugotit\elinkbook（WebView2、已下載字型、字典來源）
//   2. 使用者的「文件」資料夾下的 elinkbook 目錄（書庫、字典庫、封面、匯入的書等）
// AppDataRootOverride、DocsRootOverride 只給驗證腳本把「根目錄」指到假資料夾用（出貨版不帶），
// 讓「選是」的刪除行為可以在不碰真實資料的情況下實測。
function AppDataRoot(): String;
begin
#ifdef AppDataRootOverride
  Result := '{#AppDataRootOverride}';
#else
  Result := ExpandConstant('{userappdata}');
#endif
end;

function DocsRoot(): String;
begin
#ifdef DocsRootOverride
  Result := '{#DocsRootOverride}';
#else
  Result := ExpandConstant('{userdocs}');
#endif
end;

function AppDataDir(): String;
begin
  if AppDataRoot() <> '' then
    Result := AddBackslash(AppDataRoot()) + 'cc.ugotit\elinkbook'
  else
    Result := '';
end;

function DocsAppDir(): String;
begin
  if DocsRoot() <> '' then
    Result := AddBackslash(DocsRoot()) + 'elinkbook'
  else
    Result := '';
end;

function AnyAppDataExists(): Boolean;
begin
  Result := ((AppDataDir() <> '') and DirExists(AppDataDir())) or
            ((DocsAppDir() <> '') and DirExists(DocsAppDir()));
end;

procedure DeleteAppData();
begin
  if (AppDataDir() <> '') and DirExists(AppDataDir()) then
    DelTree(AppDataDir(), True, True, True);
  if (DocsAppDir() <> '') and DirExists(DocsAppDir()) then
    DelTree(DocsAppDir(), True, True, True);
end;

// 解除安裝時詢問是否同時刪除 App 的所有資料（含書庫）。
// 預設按鈕為「否」；靜默解除安裝（/SILENT、/VERYSILENT）一律不詢問、不刪除。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  if UninstallSilent then
    Exit;
  if not AnyAppDataExists() then
    Exit;

  if MsgBox('是否同時刪除 elinkBook 的所有資料（包含書庫）？' + #13#10 + #13#10 +
            '將刪除以下兩個資料夾：' + #13#10 +
            '1. ' + AppDataDir() + #13#10 +
            '   （已下載的字型、字典來源、WebView 瀏覽資料）' + #13#10 +
            '2. ' + DocsAppDir() + #13#10 +
            '   （書庫、字典庫、封面、匯入的書的複本等）' + #13#10 + #13#10 +
            '不會動「文件」資料夾內的其他檔案；匯入時留在原位置的書檔也不會被刪除。' + #13#10 +
            '刪除後無法復原。選「否」會保留所有資料，之後重新安裝仍可沿用。',
            mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    DeleteAppData();
end;
