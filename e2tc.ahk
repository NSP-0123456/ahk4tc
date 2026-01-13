#Requires AutoHotkey v2.0
#SingleInstance Force

;==================== CONSTANTS ==========================
WM_COMMAND := 0x0111
WM_SYSCOMMAND := 0x0112


UI_ID_FILE_COPY_FULL_PATH_AND_NAME  := 41007
UI_ID_FILE_CLOSE                    := 40011
UI_ID_FILE_CLOSE_TAB                := 40018
UI_ID_EDIT_SELECT_ALL               := 40023
UI_ID_EDIT_INVERT_SELECTION         := 40029


SetWorkingDir A_ScriptDir
iniFile := RegExReplace(A_ScriptFullPath, "(ahk|exe)$", "ini")



;==================== OUT OF THE BOX SETTINGS

	OOB_LOADLISTfilename        := "Everything.lst"
	OOB_TCexecutable 	        := "%COMMANDER_EXE%"
	OOB_CloseEverythingWhenDone := 0
	OOB_SleepTime               := 2000
	OOB_IconPosition            := "TR"


;==================== READ INI

;  Read settings from INI file
   LoadlistFilename    := ResolveEnvVars( IniRead( IniFile, "General", "LOADLIST_Filename", OOB_LOADLISTfilename) )
   TCexecutable     := ResolveEnvVars( IniRead( IniFile, "General", "TCexecutable",     OOB_TCexecutable) )
   IconPosition     := IniRead( IniFile, "General", "IconPosition", OOB_IconPosition)
   CloseEverythingWhenDone := IniRead( IniFile, "General", "CloseEverythingWhenDone", OOB_CloseEverythingWhenDone)
	SleepTime := IniRead( IniFile, "General", "SleepTime", OOB_SleepTime)
	; Ensure LOADLIST path is absolute; if not, make it relative to script dir
	if !RegExMatch(LoadlistFilename, "^(?:[A-Za-z]:|\\\\)") {
		LoadlistFilename := A_ScriptDir "\" LoadlistFilename
	}


;==================== CHECK INI

	If !FileExist(TCexecutable)
	{
		;SetTitleMatchMode "RegEx"
		tcWinIDs := WinGetList("ahk_class TTOTAL_CMD")
		if tcWinIDs.Length > 0
		{
			tcWinID := tcWinIDs[1]
			TCexecutable := WinGetProcessPath("ahk_id " tcWinID)
		}

		; If still not found, prompt user to select
		If !FileExist(TCexecutable)
		{
			TCexecutable := FileSelect(3,"C:\", "Select Total Commander executable to use", "Executable (TOTALCMD*.exe)")
			If ! FileExist(TCexecutable)
			{
				MsgBox "No Total Commander executable found.`nProgram will EXIT`nPlease try again"
				ExitApp
			}
		}
	}

;==================== WRITE INI
;	Case insensitive comparison (only if INI file doesn't exist)
	If !FileExist(IniFile)
	{
		IniWrite OOB_LOADLISTfilename, IniFile, "General", "LOADLIST_Filename"
		IniWrite OOB_TCexecutable, IniFile, "General", "TCexecutable"
		IniWrite OOB_CloseEverythingWhenDone, IniFile, "General", "CloseEverythingWhenDone"
		IniWrite OOB_IconPosition, IniFile, "General", "IconPosition"
		IniWrite OOB_SleepTime, IniFile, "General", "SleepTime"
	}
;================================ Show Icon when starting
num := ShowE2TCIcon(IconPosition)

;=================== GET Result using clipboard and open TC
{
	SetTitleMatchMode "RegEx"
	winIDs := WinGetList("ahk_exe Everything(64)?\.exe ahk_class EVERYTHING")
	if winIDs.Length > 0
	{

		winID := winIDs[1]

		If ( FileExist(LoadlistFilename) )
		{
			FileDelete LoadlistFilename
		}

		BackupClipboard := A_Clipboard
		A_Clipboard := ""


	;	Syntax : SendMessage(MsgNumber [, wParam, lParam, Control, WinTitle, WinText, ExcludeTitle, ExcludeText, Timeout])
	   result := SendMessage( WM_COMMAND, UI_ID_EDIT_SELECT_ALL               ,0,, "ahk_id " winID )
	   result := SendMessage( WM_COMMAND, UI_ID_FILE_COPY_FULL_PATH_AND_NAME  ,0,, "ahk_id " winID )
	   result := SendMessage( WM_COMMAND, UI_ID_EDIT_INVERT_SELECTION         ,0,, "ahk_id " winID )

		FileAppend A_Clipboard, LoadlistFilename
		A_Clipboard := BackupClipboard

		If (CloseEverythingWhenDone)
		{
			result := PostMessage( WM_COMMAND, UI_ID_FILE_CLOSE         ,0,, "ahk_id " winID )
		}

		TCparameters := ' /O /T /S LOADLIST:`"' . LoadlistFilename . '`"'

		Run TCexecutable TCparameters, A_ScriptDir
	} else {
		MsgBox "Everything windows not found,`r`n do a search and retry !"
	}
	Sleep SleepTime
	ExitApp
}

; ==================================
; FUNCTIONS
; ==================================
ResolveEnvVars(str) {
    ; Expand %ENVVAR% style variables using WinAPI (v2 is always Unicode)
    sz := DllCall("ExpandEnvironmentStrings", "str", str, "ptr", 0, "uint", 0, "uint")
    if (sz) {
        buf := Buffer(sz * 2) ; Wide chars (UTF-16), no need for A_IsUnicode check
        if DllCall("ExpandEnvironmentStrings", "str", str, "ptr", buf, "uint", sz, "uint")
            return StrGet(buf)
    }
    return str
}
;==================== SHOW ICON ====================
; Display e2tc.ico (or compiled exe resource) with transparent color 333333
ShowE2TCIcon(IconPos := "TR") {
	iconFile := A_ScriptDir "\e2tc.ico"
	iconSource := (A_IsCompiled && FileExist(A_ScriptFullPath)) ? A_ScriptFullPath : iconFile
	if FileExist(iconSource) {
		global iconGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "e2tc")
		iconGui.BackColor := "333333"
		WinSetTransColor("333333", iconGui)
		iconGui.Add("Picture", "Background333333 w128 h128", iconSource)

		screenWidth := A_ScreenWidth
		screenHeight := A_ScreenHeight
		iconWidth := 128
		iconHeight := 128
		margin := 8

		; Calculate position based on IconPos parameter
		switch IconPos {
			case "TL": ; Top Left
				xPos := margin
				yPos := margin
			case "TR": ; Top Right
				xPos := screenWidth - iconWidth - margin
				yPos := margin
			case "TC": ; Top Center
				xPos := (screenWidth - iconWidth) // 2
				yPos := margin
			case "BL": ; Bottom Left
				xPos := margin
				yPos := screenHeight - iconHeight - margin
			case "BR": ; Bottom Right
				xPos := screenWidth - iconWidth - margin
				yPos := screenHeight - iconHeight - margin
			case "BC": ; Bottom Center
				xPos := (screenWidth - iconWidth) // 2
				yPos := screenHeight - iconHeight - margin
			default: ; Default to Top Right
				xPos := screenWidth - iconWidth - margin
				yPos := margin
		}

		iconGui.Show("x" xPos " y" yPos " NoActivate")
	}
}

