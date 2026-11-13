; elinkBook Windows 安裝程式（Inno Setup 6）— epic-66 Issue 27
; 由 app/tool/package_windows_installer.ps1 以 iscc /D 傳入下列定義後編譯：
;   AppVersion、VersionInfoVersion、StageDir、OutputDir、OutputBaseFilename
;   AppIdOverride（可選，只給變異驗證用；未給則使用下方固定 AppId）

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

// 解除安裝時詢問是否同時刪除 %APPDATA%\cc.ugotit\elinkbook（App 設定與下載資料）。
// 注意：書庫（library.db）、封面與匯入的書放在使用者的「文件」資料夾，不在這裡，也不會被刪除。
// 預設按鈕為「否」；靜默解除安裝（/SILENT、/VERYSILENT）一律不詢問、不刪除。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  if UninstallSilent then
    Exit;

  DataDir := ExpandConstant('{userappdata}\cc.ugotit\elinkbook');
  if not DirExists(DataDir) then
    Exit;

  if MsgBox('是否同時刪除 elinkBook 的設定與下載資料？' + #13#10 + #13#10 +
            '資料夾位置：' + DataDir + #13#10 +
            '內容：已下載的字型、字典來源、WebView 瀏覽資料。刪除後無法復原。' + #13#10 + #13#10 +
            '注意：書庫（library.db）、封面與匯入的書放在「文件」資料夾，不會被刪除；如要一併清除請自行刪除。',
            mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    DelTree(DataDir, True, True, True);
end;
