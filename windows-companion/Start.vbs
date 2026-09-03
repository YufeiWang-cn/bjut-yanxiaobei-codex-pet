Option Explicit
Dim shell, fso, appRoot, host, mode, entry, args, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
appRoot = fso.GetParentFolderName(WScript.ScriptFullName)
host = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
mode = "pet"
If WScript.Arguments.Count > 0 Then mode = LCase(WScript.Arguments(0))
entry = "Launch.ps1"
args = ""
If mode = "watch" Then args = " -Watch"
shell.CurrentDirectory = appRoot
result = shell.Run("""" & host & """ -NoProfile -ExecutionPolicy Bypass -STA -File """ & fso.BuildPath(appRoot, entry) & """" & args, 0, False)
