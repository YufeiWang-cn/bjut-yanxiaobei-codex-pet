Option Explicit
Dim shell, fso, source, tempScript, installRoot, command, i, value
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
source = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Uninstaller.ps1")
installRoot = fso.GetParentFolderName(source)
If Not fso.FileExists(source) Then source = fso.BuildPath(fso.BuildPath(installRoot, "windows-companion"), "Uninstaller.ps1")
If Not fso.FileExists(fso.BuildPath(installRoot, "VERSION.txt")) Then installRoot = fso.GetParentFolderName(installRoot)
tempScript = fso.BuildPath(fso.GetSpecialFolder(2), "YanXiaoBei-Uninstaller-" & Replace(Replace(CStr(Timer), ".", ""), ",", "") & ".ps1")
fso.CopyFile source, tempScript, True
command = """" & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & _
  """ -NoProfile -ExecutionPolicy Bypass -STA -File """ & tempScript & """ -InstallRoot """ & installRoot & """"
For i = 0 To WScript.Arguments.Count - 1
  value = Replace(WScript.Arguments(i), """", "")
  command = command & " """ & value & """"
Next
shell.Run command, 0, False
