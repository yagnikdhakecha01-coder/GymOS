' GymOS Silent Background Runner (Compatible with Windows 7, 8, 10, 11)
' Runs Node.js bridge in completely silent/invisible mode (WindowStyle = 0)
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
strScriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Change working directory
WshShell.CurrentDirectory = strScriptDir

' Run the bridge invisibly without opening any black CMD window
strCommand = "cmd /c ""cd /d """ & strScriptDir & """ && node gymos_biometric_bridge.js >> gymos_bridge.log 2>&1"""
WshShell.Run strCommand, 0, False
