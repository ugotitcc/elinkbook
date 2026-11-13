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
