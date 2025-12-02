#Requires AutoHotkey v2.0
#SingleInstance Force

; -----------------------------
; Globals / Config
; -----------------------------
Version := "2.0"
ScriptName := "VP Script Editor v" Version
SelectedIcn := 0
EditOnly := false

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
; -----------------------------
; INI helpers
; -----------------------------
GetIni() {
    return ResolveEnvVars("%APPDATA%\\VPScriptEdit.ini")
}

IniGet(section, key, default := "") {
    ini := GetIni()
    value := IniRead(ini, section, key, default)
    return value
}

IniSet(section, key, value) {
    ini := GetIni()
    IniWrite(value, ini, section, key)
}

; -----------------------------
; GUI setup (minimal scaffold)
; -----------------------------
class AppGUI {
    __New(args) {
        this.args := args
        this.vpRoot := ""
        this.currentVPP := ""
        this.node := ""
        this.tmpIco := ""
        this.fileTmp := A_Temp "\\" A_Sec A_Mon A_Hour A_MSec ".scvp"
        this.gui := Gui("+Resize", ScriptName)
        this.BuildGui()
    }

    BuildGui() {
        g := this.gui
        g.OnEvent("Close", (*) => this.OnExit())
        g.MarginX := 10, g.MarginY := 10

        ; Top selection area
        this.grpSelect := g.AddGroupBox("xm ym w260 h80", "Select")
        ; File/Folder radios on same horizontal line
        this.radFile := g.AddRadio("xp+10 yp Checked", "File")
        this.radFolder := g.AddRadio("xp+70 yp", "Folder")
        this.scanItem := g.AddEdit("xp+80 yp w300", "")
        this.btnBrowse := g.AddButton("x+5 yp w40", "&...")
        this.btnBrowse.OnEvent("Click", (*) => this.OnBrowse())
        this.btnClearIcn := g.AddButton("x+5 yp w70", "&No Icon")
        this.btnClearIcn.OnEvent("Click", (*) => this.OnClearIcon())
        this.btnScan := g.AddButton("x+5 yp w55", "s&Can")
        this.btnScan.OnEvent("Click", (*) => this.OnScanToggle())
        this.txtIconsFound := g.AddText("xm y+5 w240", "0 icons found")

        ; ListView occupies central area (temporary size; resized in OnSize)
        this.lv := g.AddListView("xm y+5 w700 h300", ["Icon#","File name","Internal ID"])
        this.lv.OnEvent("ItemSelect", (ctrl, row, selected) => this.OnLVSelect(row, selected))
        ; Create ImageLists for icons (small and large)
        this.ilSmall := IL_Create(512, 512, false)
        this.ilLarge := IL_Create(512, 512, true)
        ; Attach imagelist and default to Report layout
        this.lv.SetImageList(this.ilSmall)
        this.lv.Opt("+Report")
        ; Prevent initial flashing; enable after first SetLVMode
        this.lv.Opt("-Redraw")
        ; Ensure columns are sized correctly at startup
        this.SetLVMode("Report", false)

        ; Bottom view mode radio row (initial placement; will be moved in OnSize)
        this.radReport := g.AddRadio("xm y+10 Checked", "&Report")
        this.radTile := g.AddRadio("x+10", "&Tile")
        this.radIcons := g.AddRadio("x+10", "&Icons")
        this.radSmallIcons := g.AddRadio("x+10", "s&mall Icons")
        this.radList := g.AddRadio("x+10", "&List")
        this.radReport.OnEvent("Click", (*) => this.SetLVMode("Report"))
        this.radTile.OnEvent("Click", (*) => this.SetLVMode("Tile"))
        this.radIcons.OnEvent("Click", (*) => this.SetLVMode("Icon"))
        this.radSmallIcons.OnEvent("Click", (*) => this.SetLVMode("IconSmall"))
        this.radList.OnEvent("Click", (*) => this.SetLVMode("List"))

        ; Command preview edit
        this.cmdEdit := g.AddEdit("xm y+10 w700 ReadOnly")

        ; Action buttons row
        this.btnReload := g.AddButton("xm y+8 w130", "Reload from &VP")
        this.btnReload.OnEvent("Click", (*) => this.OnReloadFromVP())
        this.btnEditScr := g.AddButton("x+8 w110", "&Edit Script")
        this.btnEditScr.OnEvent("Click", (*) => this.OnEditScript())
        this.btnRefresh := g.AddButton("x+8 w110 Disabled", "Load &Script")
        this.btnUpdate := g.AddButton("x+8 w180", "&Update Script/Icon and Exit")
        this.btnUpdate.OnEvent("Click", (*) => this.OnUpdateScript())
        this.btnClose := g.AddButton("x+8 w80", "E&xit")
        this.btnClose.OnEvent("Click", (*) => this.OnExit())

        ; Resize handler to keep radios & buttons at bottom and ListView filling space
        g.OnEvent("Size", (g, minMax, width, height) => this.OnGuiSize(g, minMax, width, height))
    }

    OnGuiSize(g, minMax, width, height) {
        ; Calculate dynamic layout
        w := width, h := height
        margin := 10
        bottomSectionHeight := 10 ; base
        this.radReport.GetPos(, , , &radioHeight)
        this.cmdEdit.GetPos(, , , &cmdHeight)
        this.btnReload.GetPos(, , , &btnHeight)
        spacing := 8
        bottomSectionHeight := radioHeight + cmdHeight + btnHeight + spacing * 3

        ; Resize ListView
        this.txtIconsFound.GetPos(&txtX, &txtY, , &txtH)
        lvY := txtY + txtH + 5
        lvHeight := h - lvY - bottomSectionHeight - margin
        if lvHeight < 80
            lvHeight := 80
        this.lv.Move(,, w - margin*2, lvHeight)

        ; Position radio row just under ListView
        this.lv.GetPos(, &lvTop)
        radioY := lvTop + lvHeight + spacing
        ; Position radios horizontally using their widths
        this.radReport.Move(margin, radioY)
        this.radReport.GetPos(&rx, , &rw)
        x := rx + rw + 10
        this.radTile.Move(x, radioY)
        this.radTile.GetPos(&rx, , &rw)
        x := rx + rw + 10
        this.radIcons.Move(x, radioY)
        this.radIcons.GetPos(&rx, , &rw)
        x := rx + rw + 10
        this.radSmallIcons.Move(x, radioY)
        this.radSmallIcons.GetPos(&rx, , &rw)
        x := rx + rw + 10
        this.radList.Move(x, radioY)

        ; Command preview just below radios
        cmdY := radioY + radioHeight + spacing
        this.cmdEdit.Move(margin, cmdY, w - margin*2)

        ; Buttons row at bottom
        btnY := cmdY + cmdHeight + spacing
        bx := margin
        this.btnReload.Move(bx, btnY)
        this.btnReload.GetPos(, , &bw)
        bx += bw + 8
        this.btnEditScr.Move(bx, btnY)
        this.btnEditScr.GetPos(, , &bw)
        bx += bw + 8
        this.btnRefresh.Move(bx, btnY)
        this.btnRefresh.GetPos(, , &bw)
        bx += bw + 8
        this.btnUpdate.Move(bx, btnY)
        this.btnUpdate.GetPos(, , &bw)
        bx += bw + 8
        this.btnClose.Move(bx, btnY)
    }
    Show() {
        this.gui.Show()
    }

    ; --------------- Events ---------------
    OnExit(*) {
        ; Persist view prefs
        try IniSet("Settings", "RadFile", (this.HasOwnProp("radFile") && this.radFile.Value) ? 1 : 2)
        try IniSet("Settings", "RadReport", (this.HasOwnProp("radReport") && this.radReport.Value) ? 1 : 0)
        try IniSet("Settings", "RadTile", (this.HasOwnProp("radTile") && this.radTile.Value) ? 1 : 0)
        try IniSet("Settings", "RadIcons", (this.HasOwnProp("radIcons") && this.radIcons.Value) ? 1 : 0)
        try IniSet("Settings", "RadSmallIcons", (this.HasOwnProp("radSmallIcons") && this.radSmallIcons.Value) ? 1 : 0)
        try IniSet("Settings", "RadList", (this.HasOwnProp("radList") && this.radList.Value) ? 1 : 0)
        try FileDelete(this.fileTmp)
        ExitApp()
    }

    OnBrowse() {
        item := this.scanItem.Text
        if this.radFile.Value {
            f := FileSelect("3", ResolveEnvVars(item), "Select file to search icons", "Files with icons (*.exe; *.dll; *.icl; *.ico; *.ani; *.cpl)")
            if f {
                this.scanItem.Value := f
                this.ScanFile(f)
            }
        } else {
            dir := DirSelect(ResolveEnvVars(item), 2, "Select folder to search icons")
            if dir {
                this.scanItem.Value := dir
                this.ScanFolder(dir)
            }
        }
    }

    OnClearIcon() {
        this.scanItem.Value := "<NO ICON>"
        this.lv.Delete()
        this.tmpIco := ""
        this.cmdEdit.Value := this.CurrentCmd()
    }

    OnScanToggle() {
        item := ResolveEnvVars(this.scanItem.Text)
        if item = ""
            return
        (DirExist(item) ? this.ScanFolder(item) : this.ScanFile(item))
    }

    OnReloadFromVP() {
        ; Re-fetch script from VP via WM_COPYDATA and read temp file
        ; v1 used /f vs /af based on Unicode; v2 is Unicode so use /f
        if this.currentVPP = "" || this.vpRoot = "" || this.node = "" {
            this.cmdEdit.Value := this.CurrentCmd()
            return
        }
        cmd := "<silent<export /f " Chr(34) this.fileTmp Chr(34) " " Chr(34) this.currentVPP Chr(34) "  {" Chr(34) this.node Chr(34) "}"
        Send_VPCmd(cmd, this.vpRoot, this.currentVPP)
        ; Load first line and format
        try {
            content := FileRead(this.fileTmp)
            firstLine := StrSplit(content, "`n")[1]
            ; Strip icon tail if present
            if RegExMatch(firstLine, "<<([^<>]+)$", &m) {
                this.tmpIco := m[0]
                firstLine := SubStr(firstLine, 1, m.Pos - 1)
            } else {
                this.tmpIco := ""
            }
            ; Indentation (simple)
            formatted := doVPIndent(firstLine) "`n"
            FileDelete(this.fileTmp)
            FileAppend(formatted, this.fileTmp, "UTF-16")
            this.cmdEdit.Value := this.CurrentCmd()
        } catch {
            this.cmdEdit.Value := this.CurrentCmd()
        }
        if this.tmpIco != "" {
            filePath := ""
            iconIdx := ""
            ParseIconInfo(this.tmpIco, &filePath, &iconIdx)
            if filePath != "" {
                this.scanItem.Value := filePath
                if DirExist(filePath) {
                    this.ScanFolder(filePath)
                } else {
                    this.ScanFile(filePath)
                }
                ; Try select matching row (fallback to first row if not found)
                if iconIdx != "" {
                    if ! SelectIconRow(this.lv, filePath, iconIdx) {
                        if this.lv.GetCount() >= 1
                            this.lv.Modify(1, "Vis +Select +Focus")
                    }
                } else {
                    ; If no index provided, select first matching file row
                    if !SelectIconRow(this.lv, filePath, "") {
                        if this.lv.GetCount() >= 1
                            this.lv.Modify(1, "Vis +Select +Focus")
                    }
                }
            }
            this.SetIconFocus()
        }


    }

    OnEditScript() {
        editor := IniGet("Settings", "editor", "notepad.exe")
        Run(editor " " Chr(34) this.fileTmp Chr(34))
        this.btnRefresh.Enabled := true
    }

    SetLVMode(mode,refresh := true ) {
        switch mode {
            case "Report": this.lv.Opt("+Report"), this.lv.SetImageList(this.ilSmall)
            case "Tile": this.lv.Opt("+Tile"), this.lv.SetImageList(this.ilLarge)
            case "Icon": this.lv.Opt("+Icon"), this.lv.SetImageList(this.ilLarge)
            case "IconSmall": this.lv.Opt("+IconSmall"), this.lv.SetImageList(this.ilSmall)
            case "List": this.lv.Opt("+List"), this.lv.SetImageList(this.ilSmall)
        }
          if (mode = "Report") {
            this.lv.GetPos(, , &lvW)
            this.lv.ModifyCol(1, 50 ) ; Icon#
            this.lv.ModifyCol(2, Max(500, Floor((lvW ? lvW : 700) * 0.60)))
            this.lv.ModifyCol(3, "AutoHdr")
        }
          ; Re-enable redraw after first mode set
          this.lv.Opt("+Redraw")
          if refresh
              this.SetIconFocus()
    }
    SetIconFocus() {
        if !this.HasOwnProp("lv")
            return
        sel := this.lv.GetNext(0, "Focused") ; focused
        if !sel
            sel := this.lv.GetNext(0, "C") ; selected
        if !sel && this.lv.GetCount() > 0
            sel := 1
        if sel
            this.lv.Modify(sel, "Vis +Focus +Select")

    }
    CurrentLVMode() {
        if this.HasOwnProp("radReport") && this.radReport.Value
            return "Report"
        if this.HasOwnProp("radTile") && this.radTile.Value
            return "Tile"
        if this.HasOwnProp("radIcons") && this.radIcons.Value
            return "Icon"
        if this.HasOwnProp("radSmallIcons") && this.radSmallIcons.Value
            return "IconSmall"
        if this.HasOwnProp("radList") && this.radList.Value
            return "List"
        return "Report"
    }

    OnUpdateScript() {
        ; Compose message and send (wrapped to suppress DLL load/timeout errors)
        cmd := "<silent<add /f " Chr(34) this.currentVPP "\\" this.node Chr(34) "  {" this.ReadTmpScript() this.tmpIco "} <flush"
        try {
            Send_VPCmd(cmd, this.vpRoot, this.currentVPP)
        } catch {
        }
        this.OnExit()
    }

    OnLVSelect(row, selected) {
        if !selected || row <= 0
            return
        ; Read row data
        iconNum := this.lv.GetText(row, 1)
        filePath := this.lv.GetText(row, 2)
        ; Update command preview tmpIco
        if (iconNum != "" && RegExMatch(iconNum, "^\d+$")) {
            this.tmpIco := "<<" filePath "," iconNum
        } else {
            this.tmpIco := "<<" filePath
        }
        this.cmdEdit.Value := this.CurrentCmd()
    }

    ; --------------- Helpers ---------------
    CurrentCmd() {
        ; Returns the composed command preview
        base := this.ReadTmpScript()
        return base (this.tmpIco ? this.tmpIco : "")
    }

    ReadTmpScript() {
        try {
            content := FileRead(this.fileTmp)
            ; Trim lines similar to sTrim
            lines := []
            for line in StrSplit(content, "`n") {
                line := Trim(line, " `t`r")
                if line != ""
                    lines.Push(line)
            }
            ; Simple join without separator
            out := ""
            for v in lines
                out .= v
            return out
        } catch {
            return ""
        }
    }

    ScanFile(path) {
        ; Extract icons and display using imagelist
        this.lv.Opt("-Redraw")
        this.lv.Delete()
        ; Ensure ListView is in the current mode before populating
        
        i := 0
        idx := 1
        ; Populate both image lists so switching modes works
        while true {
            idL := IL_Add(this.ilLarge, path, idx)
            idS := IL_Add(this.ilSmall, path, idx)
            if (idL > 0 || idS > 0) {
                i++
                this.lv.Add("Icon" . (idL ? idL : idS), idx - 1, path, i)
                idx++
                if idx > 9999
                    break
            } else {
                break
            }
        }
        this.txtIconsFound.Value := i " icons found, shown as"
        ; Do not alter tmpIco or selection here; wait for user selection
        this.cmdEdit.Value := this.CurrentCmd()
        this.lv.Opt("+Redraw")
        this.SetLVMode(this.CurrentLVMode(), true)
    }

    ScanFolder(dir) {
        this.lv.Opt("-Redraw")
        this.lv.Delete()
        ; Ensure ListView is in the current mode before populating
        this.SetLVMode(this.CurrentLVMode(), false)
        count := 0
        Loop Files dir "\*", "F" {
            file := A_LoopFileFullPath
            ; Try add first icon of each file
            idL := IL_Add(this.ilLarge, file, 1)
            idS := IL_Add(this.ilSmall, file, 1)
            if (idL > 0 || idS > 0) {
                count += 1
                this.lv.Add("Icon" . (idL ? idL : idS), 0, file, count)
                if count >= 500
                    break
            }
        }
        this.txtIconsFound.Value := count " icons found, shown as"
        ; Do not alter tmpIco or selection here; wait for user selection
        this.cmdEdit.Value := this.CurrentCmd()
        this.lv.Opt("+Redraw")
    }
}

; -----------------------------
; Entry point
; -----------------------------
main(args) {
    app := AppGUI(args)
    ; Robust arg parsing and initialization
    fnode := ""
    if args.Length >= 1 {
        fnode := args[1]
    }

    ; If fnode is a file path, extract vpRoot and node from its first line
    if fnode != "" && FileExist(fnode) {
        try {
            ; Read as UTF-8 to handle default encoding
            content := FileRead(fnode, "UTF-8")
            first := StrSplit(content, "`n")[1]
            ; Normalize CRLF
            first := StrReplace(first, "`r")
            local tempoR

            if RegExMatch(first, "^\\\\\\([^\\]+)\\[^>]*(>.+)?$", &tempoR){
                app.vpRoot := tempoR[1]
                app.node := tempoR[2]
            }
        } catch {
            ; ignore and continue
        }
    } else if fnode != "" {
        ; If fnode looks like a node (starts with '>'), set node directly
        if SubStr(fnode, 1, 1) = ">" {
            app.node := fnode
        }
    }

    ; Resolve CurrentVPP from env like v1 `${%VPRoot%}Path`
    if app.vpRoot != "" {
        envName := "${" . app.vpRoot . "}Path"
        app.currentVPP := EnvGet(envName)
    }
    ; Update window title if info present
    if app.currentVPP != "" && app.node != "" {
        app.gui.Title := ScriptName "    : " app.currentVPP app.node
    } else {
        app.gui.Title := ScriptName
    }

    ; Always show the GUI
    app.Show()

    ; If we have VPP context, load script and apply icon from code
    if app.currentVPP != "" && app.vpRoot != "" && app.node != "" {
        app.OnReloadFromVP()
        ; If code contains icon info, scan and select

    }
}

; Collect CLI args and determine EditOnly and node
main(A_Args)

; -----------------------------
doVPIndent(cmd) {
    indent := 0
    out := ""
    state := 0
    oldstate := 0
    line := Trim(cmd)
    for c in StrSplit(line, "") {
        if c = '"' {
            if state < 0 {
                state := oldstate
            } else {
                oldstate := state
                state := -1
            }
        } else if c = '<' {
            if state = 0 {
                state := 1
            } else if state > 0 {
                out .= "`r`n" . Repeat("`t", indent)
            }
        } else if (c = '}' && state >= 0) {
            indent -= 1
            out .= "`r`n" . Repeat("`t", indent)
        } else if (c = '{' && state >= 0) {
            indent += 1
        }
        out .= c
    }
    return out
}

Repeat(s, n) {
    r := ""
    loop n
        r .= s
    return r
}

Send_VPCmd(cmd, vpPath := "", vpRoot := "") {
    ; WM_COPYDATA send using SendMessageTimeoutW (silent on failure)
    hwnd := WinExist("ahk_class TTOTAL_CMD")
    if !hwnd
        return 0
    SentCmd := cmd . "-" . vpRoot . "`r" . vpPath
    ; Build COPYDATASTRUCT
    cds := Buffer(A_PtrSize * 3, 0)
    NumPut("UInt", 0x500056, cds, 0) ; dwData id
    bytes := (StrLen(SentCmd) + 1) * 2
    NumPut("UPtr", bytes, cds, A_PtrSize) ; cbData
    buf := Buffer(bytes, 0)
    StrPut(SentCmd, buf, "UTF-16")
    NumPut("UPtr", buf.Ptr, cds, A_PtrSize * 2) ; lpData
    ; Call without explicit module path to avoid load issues
    msgResult := 0
    ok := DllCall("SendMessageTimeoutW", "ptr", hwnd, "uint", 0x4A, "uptr", 0, "ptr", cds,
        "uint", 0x0002, "uint", 200, "ptr*", msgResult, "int")
    return ok ? msgResult : 0
}

; Parse tmpIco string like "<<path" or "<<path,index"
ParseIconInfo(tmpIco, &filePath, &iconIdx) {
    filePath := ""
    iconIdx := ""
    if RegExMatch(tmpIco, "^<<([^,>]+),(\d+)$", &m) {
        filePath := m[1]
        iconIdx := m[2]
    } else if RegExMatch(tmpIco, "^<<([^>]+)$", &m2) {
        filePath := m2[1]
        iconIdx := ""
    }
}

; Select a ListView row matching file and icon index
SelectIconRow(lv, filePath, iconIdx) {
    row := 0
    loop lv.GetCount() {
        idx := A_Index
        icoCol := lv.GetText(idx, 1)
        fileCol := lv.GetText(idx, 2)
        if (fileCol = filePath) {
            if (iconIdx = "" || icoCol = iconIdx) {
                row := idx
                break
            }
        }
    }
    if row > 0 {
        lv.Modify(row, "Vis +Select +Focus")
        return true
    }

    return false
}