; AutoHotkey v2 script: Append untracked files to local .gitignore with UI
#Requires AutoHotkey v2.0

main := Gui("", "Git Ignore Untracked")
main.SetFont("s10")
main.Add("Text", , "Repo Root:")
tbRoot := main.Add("Edit", "w500 vRepoRoot")
btnBrowse := main.Add("Button", "x+m", "Browse...")
btnProceed := main.Add("Button", "x+m", "Proceed")
main.Add("Text", "xm y+10", "Added Entries:")
lv := main.Add("ListView", "xm w700 h300 Grid", ["Path", "Status", ""])
; Column widths: adjust dynamically to avoid horizontal scrollbar
AdjustCols(lv)
statusTxt := main.Add("Text", "xm w700 cGray", "")

; Initialize with optional CLI arg or detected repo
repoRoot := ""
if A_Args.Length >= 1 {
    repoRoot := Trim(A_Args[1])
}
if (repoRoot = "") {
    repoRoot := GetRepoRoot()
}
tbRoot.Value := repoRoot

btnBrowse.OnEvent("Click", (*) => OnBrowse(tbRoot))
btnProceed.OnEvent("Click", (*) => OnProceed(tbRoot, lv, statusTxt))
main.OnEvent("Size", (*) => AdjustCols(lv))

main.Show()
return

OnBrowse(tb) {
    start := Trim(tb.Value)
    dir := FileSelect("D", start, "Select Git Repo Root")
    if dir != "" {
        tb.Value := dir
    }
}

OnProceed(tb, lv, st) {
    lv.Delete()
    st.Value := ""
    root := Trim(tb.Value)
    if (root = "") {
        st.Value := "Please select a repository root."
        return
    }
    root := RTrim(root, "\\/")
    if !DirExist(root) {
        st.Value := "Path does not exist: " root
        return
    }
    if !DirExist(root "\\.git") {
        st.Value := "Not a git repository: " root
        return
    }
    status := GetPorcelainStatus(root)
    untracked := ParseUntracked(status)
    if untracked.Length = 0 {
        st.Value := "#### No unstaged Files ####"
        return
    }
    ignoreFile := root "\\.git\\info\\exclude"
    ; Ensure exclude file exists
    if !FileExist(ignoreFile) {
        ; Create parent folder if missing (should exist), then empty file
        FileAppend("", ignoreFile, "UTF-8")
    }
    existing := FileExist(ignoreFile) ? FileRead(ignoreFile, "UTF-8") : ""
    existingSet := StrSplitToSet(existing)
    added := 0
    toAdd := []
    for idx, fpath in untracked {
        rel := NormalizePath(RelativePath(root, fpath))
        if rel = "" {
            continue
        }
        ; Skip if path is tracked by git (present locally/remote history)
        if IsTracked(root, rel) {
            sym := "🟦" ; cyan-ish indicator
            lv.Add(, rel, "Remote", sym)
            continue
        }
        if !existingSet.Has(rel) {
            toAdd.Push(rel)
            existingSet[rel] := true
            sym := "🟩" ; light green indicator
            lv.Add(, rel, "Added", sym)
            added++
        } else {
            sym := "⚪" ; light grey-ish indicator
            lv.Add(, rel, "Present", sym)
        }
    }
    if (added > 0) {
        ; Ensure header starts on a new line (but avoid double blank lines)
        prefix := ""
        if (existing != "") {
            last := SubStr(existing, StrLen(existing), 1)
            if (last != "`n") {
                prefix := "`n"
            }
        }
        FileAppend(prefix . "#### GitIgnore Untracked from AHK Script`n", ignoreFile, "UTF-8")
        for _, rel in toAdd {
            FileAppend(rel "`n", ignoreFile, "UTF-8")
        }
        FileAppend("#### EndOf AHK GitIgnore Untracked`n", ignoreFile, "UTF-8")
    }
    ; readjust columns after rows added
    AdjustCols(lv)
    if (added = 0) {
        st.Value := "#### No unstaged Files ####"
    } else {
        st.Value := "Added " added " entr" (added=1?"y":"ies") " to .git/info/exclude"
    }
}

; ---------------- Helpers ----------------
GetRepoRoot() {
    proc := Exec('git rev-parse --show-toplevel')
    out := Trim(proc.StdOut.Read())
    ; if git failed, return empty to let caller handle
    if (out = "") {
        return ""
    }
    return out
}

GetPorcelainStatus(repoRoot) {
    proc := Exec('git -C "' repoRoot '" status --porcelain')
    out := proc.StdOut.Read()
    ; ignore stderr to avoid message dialogs
    return out
}

IsTracked(repoRoot, relPath) {
    ; Returns true if the path is tracked by git
    cmd := 'git -C "' repoRoot '" ls-files --error-unmatch "' relPath '"'
    r := Exec(cmd)
    ; ls-files writes the path to stdout when matched; empty on error-unmatch
    return Trim(r.StdOut.Read()) != ""
}

ParseUntracked(statusText) {
    arr := []
    for line in StrSplit(statusText, "`n", "`r") {
        line := Trim(line)
        if (line = "")
            continue
        ; Porcelain format: "?? <path>" for untracked
        if SubStr(line, 1, 2) = "??" {
            path := Trim(SubStr(line, 4))
            if path != ""
                arr.Push(path)
        }
    }
    return arr
}

RelativePath(base, path) {
    ; If path is already relative, return as-is
    if !RegExMatch(path, '^[A-Za-z]:\\') && !RegExMatch(path, '^/') {
        return path
    }
    base := RTrim(base, "\\/")
    abs := path
    ; If absolute path starts with repo root, strip it to get relative
    if (SubStr(abs, 1, StrLen(base)) = base) {
        ; Remove trailing separator
        sep := SubStr(abs, StrLen(base) + 1, 1)
        rel := SubStr(abs, StrLen(base) + (sep="\\" || sep="/" ? 2 : 1))
        return rel
    }
    return abs
}

NormalizePath(p) {
    ; Replace backslashes with forward slashes to be .gitignore-friendly
    p := StrReplace(p, "\\", "/")
    ; Strip leading ./ if present
    if SubStr(p, 1, 2) = "./"
        p := SubStr(p, 3)
    return p
}

StrSplitToSet(text) {
    set := Map()
    for line in StrSplit(text, "`n", "`r") {
        l := Trim(line)
        if l = ""
            continue
        set[l] := true
    }
    return set
}

; Lightweight Exec wrapper capturing stdout/stderr via temp files
Exec(cmd) {
    outFile := A_Temp "\\ahk_exec_out_" A_TickCount ".txt"
    errFile := A_Temp "\\ahk_exec_err_" A_TickCount ".txt"
    q := Chr(34)
    full := A_ComSpec . " /c " . cmd . " > " . q . outFile . q . " 2> " . q . errFile . q
    RunWait(full, , "Hide")
    out := FileExist(outFile) ? FileRead(outFile, "UTF-8") : ""
    err := FileExist(errFile) ? FileRead(errFile, "UTF-8") : ""
    ; Clean up temp files
    if FileExist(outFile) {
        FileDelete(outFile)
    }
    if FileExist(errFile) {
        FileDelete(errFile)
    }
    return {
        StdOut: { Read: (*) => out },
        StdErr: { Read: (*) => err },
        ExitCode: 0
    }
}

; ---- UI helpers ----
AdjustCols(lv) {
    ; Compute available width and set Path to fill, Status proportion, Color fixed 40px
    lv.GetPos(, , &w, )
    colorW := 40
    ; 80% Path, 18% Status, 2% padding (applied between Path and Status)
    baseW := w - colorW
    pathW := Floor(baseW * 0.80)
    statusW := Floor(baseW * 0.18)
    pad := Max(Floor(baseW * 0.02), 0)
    ; Ensure minimums
    if (pathW < 100) {
        pathW := 100
    }
    if (statusW < 60) {
        statusW := 60
    }
    ; Fit within available width
    total := pathW + statusW + pad + colorW
    if (total > w) {
        extra := total - w
        ; Trim pad then path
        pad := Max(pad - extra, 0)
        total := pathW + statusW + pad + colorW
        if (total > w) {
            pathW := Max(pathW - (total - w), 100)
        }
    }
    lv.ModifyCol(1, pathW)
    lv.ModifyCol(2, statusW)
    lv.ModifyCol(3, colorW)
}
