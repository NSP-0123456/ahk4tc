;# NotNull, Horst.Epp
;# 26/11/2025 18:28:58

;#Requires AutoHotkey v2.0
;#SingleInstance Force

;==================== CONSTANTS ==========================
WM_COMMAND := 0x0111
WM_SYSCOMMAND := 0x0112


UI_ID_FILE_COPY_FULL_PATH_AND_NAME  := 41007
UI_ID_FILE_CLOSE                    := 40011
UI_ID_FILE_CLOSE_TAB                := 40018
UI_ID_EDIT_SELECT_ALL               := 40023
UI_ID_EDIT_INVERT_SELECTION         := 40029


SetWorkingDir A_ScriptDir
IniFile := "Everything2TC.ini"


;==================== OUT OF THE BOX SETTINGS

        OOB_LOADLISTfilename   := A_ScriptDir . "\Everything2TC.lst"
        OOB_TCexecutable     := "%COMMANDER_EXE%"
        OOB_CloseEverythingWhenDone := 0


;==================== READ INI

;  Read settings from INI file
   LoadlistFilename    := IniRead( IniFile, "General", "LOADLIST_Filename", OOB_LOADLISTfilename)
   TCexecutable     := IniRead( IniFile, "General", "TCexecutable",     OOB_TCexecutable)
   CloseEverythingWhenDone := IniRead( IniFile, "General", "CloseEverythingWhenDone", OOB_CloseEverythingWhenDone)


;==================== CHECK INI

	If !FileExist(TCexecutable)
	{
		TCexecutable := FileSelect(3,"C:\", "Select Total Commander executable to use", "Executable (TOTALCMD*.exe)")
		If !FileExist(TCexecutable)
		{
			MsgBox "No Total Commander executable found.`nProgram will EXIT`nPlease try again"
			ExitApp
		}
	}

;==================== WRITE INI
;	Case insensitive comparison 
;	IniWrite LoadlistFilename, IniFile, "General", "LOADLIST_Filename"
;	IniWrite TCexecutable, IniFile, "General", "TCexecutable"
;	IniWrite CloseEverythingWhenDone, IniFile, "General", "CloseEverythingWhenDone"

	
	WinActivate "ahk_exe Everything.exe"
        WinWaitActive "ahk_exe Everything.exe"
        winID := WinGetID("ahk_exe Everything.exe")


	If ( FileExist(LoadlistFilename) )
	{
		FileDelete LoadlistFilename
	}

	BackupClipboard := A_Clipboard
	A_Clipboard := ""

;	Syntax : SendMessage(MsgNumber [, wParam, lParam, Control, WinTitle, WinText, ExcludeTitle, ExcludeText, Timeout])
        result := SendMessage( WM_COMMAND, UI_ID_EDIT_SELECT_ALL               ,0,, "ahk_id " winID )
        result := SendMessage( WM_COMMAND, UI_ID_FILE_COPY_FULL_PATH_AND_NAME, 0,, "ahk_id " winID )

        ClipWait 0.5

	FileEncoding "UTF-16"
	FileAppend A_Clipboard, LoadlistFilename
	A_Clipboard := BackupClipboard

	If (CloseEverythingWhenDone)
	{
		result := PostMessage( WM_COMMAND, UI_ID_FILE_CLOSE         ,0,, "ahk_id " winID )
	}

	TCparameters := ' /O /T /S LOADLIST:`"' . LoadlistFilename . '`"'
	
	Run TCexecutable TCparameters
