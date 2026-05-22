; ---------------------------------------------------------------------
; Script runner module:
; - Folder-based script discovery
; - Extension-to-interpreter mapping
; - Safe run/paste guards and execution helpers
; ---------------------------------------------------------------------

; Initializes default script runner state and built-in mappings.
ScriptRunnerInitDefaults() {
    global _ScriptRunnerState

    if IsObject(_ScriptRunnerState)
        return

    _ScriptRunnerState := {
        enabled: false,
        folder: "",
        invocationFolder: "",
        recursive: false,
        requireConfirm: true,
        showConsole: true,
        waitForExit: false,
        maxItems: 80,
        mapping: Map(),
        cacheTick: 0,
        cacheItems: [],
        lastError: ""
    }

    ScriptRunnerEnsureDefaultMappings()
}

; Ensures built-in language mappings exist.
ScriptRunnerEnsureDefaultMappings() {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    mapping := _ScriptRunnerState.mapping

    if !mapping.Has(".ps1")
        mapping[".ps1"] := {runnerExe: "pwsh.exe", argsTemplate: '-NoProfile -ExecutionPolicy Bypass -File "{script}"'}
    if !mapping.Has(".py")
        mapping[".py"] := {runnerExe: "python.exe", argsTemplate: '"{script}"'}
    if !mapping.Has(".js")
        mapping[".js"] := {runnerExe: "node.exe", argsTemplate: '"{script}"'}
    if !mapping.Has(".ahk")
        mapping[".ahk"] := {runnerExe: "AutoHotkey64.exe", argsTemplate: '"{script}"'}
    if !mapping.Has(".cmd")
        mapping[".cmd"] := {runnerExe: "cmd.exe", argsTemplate: '/c "{script}"'}
    if !mapping.Has(".bat")
        mapping[".bat"] := {runnerExe: "cmd.exe", argsTemplate: '/c "{script}"'}
}

; Returns whether script functionality is enabled.
ScriptRunnerIsEnabled() {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    return _ScriptRunnerState.enabled
}

; Loads script-runner settings from settings.ini.
ScriptRunnerLoadFromSettings() {
    global SettingsFile, _ScriptRunnerState

    ScriptRunnerInitDefaults()
    state := _ScriptRunnerState

    state.mapping := Map()
    ScriptRunnerEnsureDefaultMappings()
    state.invocationFolder := ""

    if !FileExist(SettingsFile) {
        state.cacheTick := 0
        state.cacheItems := []
        state.lastError := ""
        return
    }

    state.enabled := (IniRead(SettingsFile, "script_runner", "enabled", state.enabled ? "1" : "0") = "1")
    state.folder := Trim(IniRead(SettingsFile, "script_runner", "folder", state.folder))
    state.folder := RegExReplace(StrReplace(state.folder, "/", "\"), "\\+$")
    state.recursive := (IniRead(SettingsFile, "script_runner", "recursive", state.recursive ? "1" : "0") = "1")
    state.requireConfirm := (IniRead(SettingsFile, "script_runner", "require_confirm", state.requireConfirm ? "1" : "0") = "1")
    state.showConsole := (IniRead(SettingsFile, "script_runner", "show_console", state.showConsole ? "1" : "0") = "1")
    state.waitForExit := (IniRead(SettingsFile, "script_runner", "wait_for_exit", state.waitForExit ? "1" : "0") = "1")

    maxItemsRaw := Trim(IniRead(SettingsFile, "script_runner", "max_items", state.maxItems ""))
    if RegExMatch(maxItemsRaw, "^-?\d+$")
        maxItems := maxItemsRaw + 0
    else
        maxItems := state.maxItems
    if (maxItems < 1)
        maxItems := 1
    if (maxItems > 300)
        maxItems := 300
    state.maxItems := maxItems

    sectionText := ""
    try sectionText := IniRead(SettingsFile, "script_runner_lang")
    catch
        sectionText := ""

    if (sectionText != "") {
        Loop Parse sectionText, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue

            eqPos := InStr(line, "=")
            if !eqPos
                continue

            ext := Trim(SubStr(line, 1, eqPos - 1))
            raw := Trim(SubStr(line, eqPos + 1))
            runnerExe := ""
            argsTemplate := ""
            if ScriptRunnerParseMappingValue(raw, &runnerExe, &argsTemplate)
                ScriptRunnerSetMapping(ext, runnerExe, argsTemplate)
        }
    }

    state.cacheTick := 0
    state.cacheItems := []
    state.lastError := ""
}

; Saves script-runner settings to settings.ini.
ScriptRunnerSaveToSettings() {
    global SettingsFile, _ScriptRunnerState

    ScriptRunnerInitDefaults()
    state := _ScriptRunnerState

    EnsureParentDirectory(SettingsFile)
    IniWrite(state.enabled ? "1" : "0", SettingsFile, "script_runner", "enabled")
    IniWrite(state.folder, SettingsFile, "script_runner", "folder")
    IniWrite(state.recursive ? "1" : "0", SettingsFile, "script_runner", "recursive")
    IniWrite(state.requireConfirm ? "1" : "0", SettingsFile, "script_runner", "require_confirm")
    IniWrite(state.showConsole ? "1" : "0", SettingsFile, "script_runner", "show_console")
    IniWrite(state.waitForExit ? "1" : "0", SettingsFile, "script_runner", "wait_for_exit")
    IniWrite(state.maxItems "", SettingsFile, "script_runner", "max_items")

    try IniDelete(SettingsFile, "script_runner_lang")

    for ext, cfg in state.mapping {
        if !cfg.HasOwnProp("runnerExe")
            continue
        runnerExe := Trim(cfg.runnerExe)
        if (runnerExe = "")
            continue
        argsTemplate := cfg.HasOwnProp("argsTemplate") ? cfg.argsTemplate : ""
        IniWrite(runnerExe "|" argsTemplate, SettingsFile, "script_runner_lang", ext)
    }
}

; Sets the script root folder and invalidates cache.
ScriptRunnerSetFolder(path) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    normalized := RegExReplace(StrReplace(Trim(path), "/", "\"), "\\+$")
    _ScriptRunnerState.folder := normalized
    _ScriptRunnerState.cacheTick := 0
    _ScriptRunnerState.cacheItems := []
    _ScriptRunnerState.lastError := ""
    return normalized
}

; Stores current folder-context path for script argument templating.
ScriptRunnerSetInvocationFolder(path := "") {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    normalized := RegExReplace(StrReplace(Trim(path), "/", "\"), "\\+$")
    _ScriptRunnerState.invocationFolder := normalized
    return normalized
}

; Returns active folder-context path used by script argument templating.
ScriptRunnerGetInvocationFolder() {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    if !_ScriptRunnerState.HasOwnProp("invocationFolder")
        _ScriptRunnerState.invocationFolder := ""
    return _ScriptRunnerState.invocationFolder
}

; Returns true if active window is Explorer and resolves a folder context path.
ScriptRunnerIsFolderContextActive(&folderPath := "") {
    folderPath := ""
    return ScriptRunnerGetActiveExplorerFolderPath(&folderPath)
}

; Resolves selected/current folder path from active Explorer window.
ScriptRunnerGetActiveExplorerFolderPath(&folderPath := "") {
    folderPath := ""

    activeHwnd := WinActive("A")
    if !activeHwnd
        return false

    className := ""
    try className := WinGetClass("ahk_id " activeHwnd)
    if (className != "CabinetWClass" && className != "ExploreWClass")
        return false

    shell := 0
    try shell := ComObject("Shell.Application")
    catch
        return false

    for win in shell.Windows {
        winHwnd := 0
        try winHwnd := win.HWND
        if !winHwnd
            continue
        if (winHwnd != activeHwnd)
            continue

        hasSelection := false
        try selected := win.Document.SelectedItems
        if IsObject(selected) {
            itemCount := 0
            try itemCount := selected.Count
            hasSelection := (itemCount > 0)
            if hasSelection {
                Loop itemCount {
                    itemPath := ""
                    try itemPath := selected.Item(A_Index - 1).Path
                    if (itemPath = "")
                        continue
                    if InStr(FileExist(itemPath), "D") {
                        folderPath := itemPath
                        return true
                    }
                }
            }
        }

        ; If Explorer has an explicit selection and none are folders, do not treat it
        ; as folder context.
        if hasSelection
            return false

        currentPath := ""
        try currentPath := win.Document.Folder.Self.Path
        if (currentPath != "") {
            folderPath := currentPath
            return true
        }
    }

    return false
}

; Refreshes cached script list and returns items.
ScriptRunnerRefreshCache(force := false) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    state := _ScriptRunnerState

    if !force {
        cacheAge := A_TickCount - state.cacheTick
        if (state.cacheTick > 0 && cacheAge >= 0 && cacheAge < 2500)
            return state.cacheItems
    }

    items := []
    state.lastError := ""

    if !state.enabled {
        state.cacheTick := A_TickCount
        state.cacheItems := items
        return items
    }

    folder := state.folder
    if (folder = "" || !DirExist(folder)) {
        state.lastError := T("msg_script_folder_missing")
        state.cacheTick := A_TickCount
        state.cacheItems := items
        return items
    }

    loopMode := state.recursive ? "FR" : "F"
    Loop Files, folder "\*.*", loopMode {
        scriptPath := A_LoopFileFullPath
        SplitPath scriptPath, &name, , &ext
        ext := ScriptRunnerNormalizeExt(ext)
        if !state.mapping.Has(ext)
            continue

        cfg := state.mapping[ext]
        items.Push({
            name: name,
            path: scriptPath,
            ext: ext,
            runnerExe: cfg.runnerExe,
            argsTemplate: cfg.argsTemplate
        })

        if (items.Length >= state.maxItems)
            break
    }

    if (items.Length > 1)
        items.Sort(ScriptRunnerCompareItemsByName)

    state.cacheTick := A_TickCount
    state.cacheItems := items
    return items
}

; Returns scripts currently eligible for menu rendering.
ScriptRunnerGetMenuItems() {
    return ScriptRunnerRefreshCache(false)
}

; Builds and returns a script menu.
ScriptRunnerBuildMenu(actionMode := "run", includeUtilities := true) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    menuObj := Menu()

    if !_ScriptRunnerState.enabled {
        menuObj.Add(T("msg_script_runner_disabled"), ScriptRunnerNoOp)
        if includeUtilities {
            menuObj.Add()
            menuObj.Add(T("settings_scripts_configure"), OpenScriptRunnerMappingDialog)
        }
        return menuObj
    }

    if includeUtilities {
        menuObj.Add(T("menu_run_script_refresh"), ScriptRunnerRefreshMenuAction.Bind(actionMode, includeUtilities))
        menuObj.Add(T("menu_run_script_open_folder"), ScriptRunnerOpenFolderAction)
        menuObj.Add(T("settings_scripts_configure"), OpenScriptRunnerMappingDialog)
        menuObj.Add()
    }

    items := ScriptRunnerGetMenuItems()
    if (items.Length = 0) {
        label := _ScriptRunnerState.lastError != "" ? _ScriptRunnerState.lastError : T("menu_run_script_empty")
        menuObj.Add(label, ScriptRunnerNoOp)
        return menuObj
    }

    for _, item in items {
        display := item.name
        if (actionMode = "paste")
            display := T("menu_script_paste_prefix") " " display
        menuObj.Add(display, ScriptRunnerMenuInvoke.Bind(item.path, actionMode))
    }

    return menuObj
}

; Dispatches script menu click by action mode.
ScriptRunnerMenuInvoke(path, actionMode := "run", *) {
    if (actionMode = "paste")
        return ScriptRunnerPasteAsText(path)
    return ScriptRunnerRun(path)
}

; Runs a script with mapped interpreter and configured options.
ScriptRunnerRun(path) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    reason := ""
    if !ScriptRunnerValidatePath(path, &reason) {
        MsgBox reason, T("menu_run_script")
        return false
    }

    if _ScriptRunnerState.requireConfirm {
        prompt := StrReplace(T("msg_script_run_confirm"), "{1}", path)
        ans := MsgBox(prompt, T("menu_run_script"), "YesNo Icon?")
        if (ans != "Yes")
            return false
    }

    exe := ""
    args := ""
    workDir := ""
    if !ScriptRunnerResolveCommand(path, &exe, &args, &workDir, &reason) {
        MsgBox reason, T("menu_run_script")
        return false
    }

    runLine := '"' exe '"'
    if (args != "")
        runLine .= " " args

    runOpts := _ScriptRunnerState.showConsole ? "" : "Hide"

    try {
        if _ScriptRunnerState.waitForExit
            RunWait(runLine, workDir, runOpts)
        else
            Run(runLine, workDir, runOpts)

        ScriptRunnerLog("RUN OK | " path " | " runLine)
        return true
    } catch as err {
        ScriptRunnerLog("RUN FAIL | " path " | " err.Message)
        msg := T("msg_script_run_failed") "`n`n" path "`n`n" err.Message
        MsgBox msg, T("menu_run_script")
        return false
    }
}

; Pastes script file contents as plain text into captured text target.
ScriptRunnerPasteAsText(path) {
    global _PendingPasteTarget

    reason := ""
    if !ScriptRunnerValidatePath(path, &reason) {
        MsgBox reason, T("menu_paste_script_text")
        return false
    }

    target := _PendingPasteTarget
    _PendingPasteTarget := 0
    if !FocusPasteTarget(target) {
        ShowTransientToolTip(T("msg_paste_target_lost"))
        return false
    }

    text := ""
    if !ScriptRunnerReadScriptText(path, &text, &reason) {
        MsgBox reason, T("menu_paste_script_text")
        return false
    }

    PastePlain(text, target)
    ScriptRunnerLog("PASTE OK | " path)
    return true
}

; Reads script text with UTF-8 and CP1252 fallback.
ScriptRunnerReadScriptText(path, &text, &reason := "") {
    text := ""
    reason := ""

    try {
        text := FileRead(path, "UTF-8")
        return true
    } catch {
    }

    try {
        text := FileRead(path, "CP1252")
        return true
    } catch as err {
        reason := T("msg_script_run_failed") "`n`n" path "`n`n" err.Message
        return false
    }
}

; Resolves final interpreter command parts for script execution.
ScriptRunnerResolveCommand(path, &exe, &args, &workDir, &reason := "") {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    reason := ""
    exe := ""
    args := ""
    workDir := ""

    SplitPath path, , &workDir, &ext
    ext := ScriptRunnerNormalizeExt(ext)
    if !_ScriptRunnerState.mapping.Has(ext) {
        reason := T("msg_script_no_mapping")
        return false
    }

    cfg := _ScriptRunnerState.mapping[ext]
    exe := Trim(cfg.runnerExe)
    if (exe = "") {
        reason := T("msg_script_no_mapping")
        return false
    }

    if (InStr(exe, "\") || InStr(exe, "/") || InStr(exe, ":")) {
        if !FileExist(exe) {
            reason := T("msg_script_run_failed") "`n`n" exe
            return false
        }
    }

    argsTemplate := cfg.argsTemplate
    quotedScript := ScriptRunnerQuoteArg(path)
    quotedFolder := ScriptRunnerQuoteArg(ScriptRunnerGetInvocationFolder())
    if InStr(argsTemplate, "{folder}")
        argsTemplate := StrReplace(argsTemplate, "{folder}", quotedFolder)
    if InStr(argsTemplate, "{script}")
        args := StrReplace(argsTemplate, "{script}", quotedScript)
    else if (Trim(argsTemplate) = "")
        args := quotedScript
    else
        args := argsTemplate " " quotedScript

    return true
}

; Validates path and extension safety before script action.
ScriptRunnerValidatePath(path, &reason := "") {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    reason := ""

    if !_ScriptRunnerState.enabled {
        reason := T("msg_script_runner_disabled")
        return false
    }

    if (path = "" || !FileExist(path)) {
        reason := T("msg_script_run_failed")
        return false
    }

    rootFolder := _ScriptRunnerState.folder
    if (rootFolder = "" || !DirExist(rootFolder)) {
        reason := T("msg_script_folder_missing")
        return false
    }

    normRoot := ScriptRunnerNormalizePath(rootFolder)
    normPath := ScriptRunnerNormalizePath(path)
    rootPrefix := normRoot "\"
    if (StrLower(normPath) != StrLower(normRoot) && SubStr(StrLower(normPath), 1, StrLen(rootPrefix)) != StrLower(rootPrefix)) {
        reason := T("msg_script_outside_folder")
        return false
    }

    SplitPath path, , , &ext
    ext := ScriptRunnerNormalizeExt(ext)
    if !_ScriptRunnerState.mapping.Has(ext) {
        reason := T("msg_script_no_mapping")
        return false
    }

    return true
}

; Opens script folder in Explorer from menu.
ScriptRunnerOpenFolderAction(*) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    folder := _ScriptRunnerState.folder
    if (folder = "" || !DirExist(folder)) {
        MsgBox T("msg_script_folder_missing"), T("menu_run_script")
        return
    }

    try Run('explorer.exe "' folder '"')
    catch
        MsgBox folder, T("menu_run_script")
}

; Refreshes script cache from script menu.
ScriptRunnerRefreshMenuAction(actionMode := "run", includeUtilities := true, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    items := ScriptRunnerRefreshCache(true)
    if (_ScriptRunnerState.lastError != "") {
        ShowTransientToolTip(_ScriptRunnerState.lastError)
        return
    }

    ShowTransientToolTip(T("settings_scripts_refresh") ": " items.Length)
}

; Opens script mapping editor dialog.
OpenScriptRunnerMappingDialog(*) {
    global _ScriptRunnerMappingWindow
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    if IsObject(_ScriptRunnerMappingWindow) {
        try {
            _ScriptRunnerMappingWindow.gui.Show()
            _ScriptRunnerMappingWindow.gui.Focus()
            return
        }
    }

    mappingGui := Gui("+Resize +MinSize640x360", T("script_mapping_title"))
    mappingGui.SetFont("s10", "Segoe UI")

    lv := mappingGui.AddListView("x10 y10 w620 h210 -Multi", [T("script_mapping_ext"), T("script_mapping_runner"), T("script_mapping_args")])
    lv.ModifyCol(1, 90)
    lv.ModifyCol(2, 170)
    lv.ModifyCol(3, 340)

    mappingGui.AddText("x10 y230 w70 h20", T("script_mapping_ext"))
    extEdit := mappingGui.AddEdit("x82 y228 w90 h24")
    mappingGui.AddText("x180 y230 w62 h20", T("script_mapping_runner"))
    runnerEdit := mappingGui.AddEdit("x246 y228 w190 h24")
    mappingGui.AddText("x10 y260 w70 h20", T("script_mapping_args"))
    argsEdit := mappingGui.AddEdit("x82 y258 w354 h24")
    mappingGui.AddText("x10 y290 w620 h20", T("script_mapping_hint"))

    btnAddUpdate := mappingGui.AddButton("x444 y228 w92 h24", T("script_mapping_add_update"))
    btnDelete := mappingGui.AddButton("x544 y228 w86 h24", T("script_mapping_delete"))
    btnSave := mappingGui.AddButton("x444 y258 w92 h24", T("script_mapping_save"))
    btnCancel := mappingGui.AddButton("x544 y258 w86 h24", T("script_mapping_cancel"))

    state := {
        gui: mappingGui,
        lv: lv,
        extEdit: extEdit,
        runnerEdit: runnerEdit,
        argsEdit: argsEdit,
        workingMap: ScriptRunnerCloneMapping(_ScriptRunnerState.mapping)
    }
    _ScriptRunnerMappingWindow := state

    ScriptRunnerMappingPopulateList(state)

    lv.OnEvent("ItemSelect", ScriptRunnerMappingSelectRow.Bind(state))
    btnAddUpdate.OnEvent("Click", ScriptRunnerMappingAddOrUpdate.Bind(state))
    btnDelete.OnEvent("Click", ScriptRunnerMappingDelete.Bind(state))
    btnSave.OnEvent("Click", ScriptRunnerMappingSave.Bind(state))
    btnCancel.OnEvent("Click", ScriptRunnerMappingClose.Bind(state))
    mappingGui.OnEvent("Close", ScriptRunnerMappingClose.Bind(state))
    mappingGui.OnEvent("Escape", ScriptRunnerMappingClose.Bind(state))

    mappingGui.Show("w640 h360")
}

; Returns a deep clone of extension mapping map.
ScriptRunnerCloneMapping(sourceMap) {
    cloned := Map()
    for ext, cfg in sourceMap {
        runner := cfg.HasOwnProp("runnerExe") ? cfg.runnerExe : ""
        args := cfg.HasOwnProp("argsTemplate") ? cfg.argsTemplate : ""
        cloned[ext] := {runnerExe: runner, argsTemplate: args}
    }
    return cloned
}

; Loads mapping rows into the mapping editor list view.
ScriptRunnerMappingPopulateList(state) {
    state.lv.Delete()

    extList := []
    for ext, _ in state.workingMap
        extList.Push(ext)

    if (extList.Length > 1)
        extList.Sort()

    for _, ext in extList {
        cfg := state.workingMap[ext]
        state.lv.Add("", ext, cfg.runnerExe, cfg.argsTemplate)
    }
}

; Handles list row selection in mapping editor.
ScriptRunnerMappingSelectRow(state, ctrl, row, selected) {
    if !selected
        return
    if (row < 1)
        return

    state.extEdit.Value := ctrl.GetText(row, 1)
    state.runnerEdit.Value := ctrl.GetText(row, 2)
    state.argsEdit.Value := ctrl.GetText(row, 3)
}

; Handles add/update row action in mapping editor.
ScriptRunnerMappingAddOrUpdate(state, *) {
    ext := ScriptRunnerNormalizeExt(state.extEdit.Value)
    runner := Trim(state.runnerEdit.Value)
    args := Trim(state.argsEdit.Value)

    if (ext = "" || runner = "") {
        MsgBox T("msg_script_mapping_invalid"), T("script_mapping_title")
        return
    }
    if (args = "")
        args := '"{script}"'

    state.workingMap[ext] := {runnerExe: runner, argsTemplate: args}
    ScriptRunnerMappingPopulateList(state)
}

; Handles delete row action in mapping editor.
ScriptRunnerMappingDelete(state, *) {
    ext := ScriptRunnerNormalizeExt(state.extEdit.Value)
    if (ext = "" || !state.workingMap.Has(ext))
        return

    state.workingMap.Delete(ext)
    ScriptRunnerMappingPopulateList(state)
    state.extEdit.Value := ""
    state.runnerEdit.Value := ""
    state.argsEdit.Value := ""
}

; Persists mapping editor changes and closes dialog.
ScriptRunnerMappingSave(state, *) {
    global _ScriptRunnerState

    _ScriptRunnerState.mapping := ScriptRunnerCloneMapping(state.workingMap)
    ScriptRunnerSaveToSettings()
    ScriptRunnerRefreshCache(true)
    ShowTransientToolTip(T("msg_script_mapping_saved"))
    ScriptRunnerMappingClose(state)
}

; Closes mapping editor without saving current working edits.
ScriptRunnerMappingClose(state, *) {
    global _ScriptRunnerMappingWindow
    try state.gui.Destroy()
    _ScriptRunnerMappingWindow := 0
}

; Writes one script-runner log line into DataRootDir.
ScriptRunnerLog(text) {
    global DataRootDir

    stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    line := stamp " | " text "`n"
    logPath := DataRootDir "\script_runner.log"

    try {
        EnsureDirectoryExists(DataRootDir)
        FileAppend(line, logPath, "UTF-8")
    }
}

; Parses one `runner|args` mapping value.
ScriptRunnerParseMappingValue(value, &runnerExe, &argsTemplate) {
    runnerExe := ""
    argsTemplate := ""

    raw := Trim(value)
    if (raw = "")
        return false

    sep := InStr(raw, "|")
    if !sep {
        runnerExe := raw
        argsTemplate := '"{script}"'
        return true
    }

    runnerExe := Trim(SubStr(raw, 1, sep - 1))
    argsTemplate := Trim(SubStr(raw, sep + 1))
    if (runnerExe = "")
        return false
    if (argsTemplate = "")
        argsTemplate := '"{script}"'
    return true
}

; Upserts one extension mapping entry.
ScriptRunnerSetMapping(ext, runnerExe, argsTemplate := "") {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()

    normExt := ScriptRunnerNormalizeExt(ext)
    runner := Trim(runnerExe)
    args := Trim(argsTemplate)
    if (normExt = "" || runner = "")
        return false
    if (args = "")
        args := '"{script}"'

    _ScriptRunnerState.mapping[normExt] := {runnerExe: runner, argsTemplate: args}
    return true
}

; Normalizes file-extension keys to `.ext` lowercase format.
ScriptRunnerNormalizeExt(ext) {
    v := StrLower(Trim(ext))
    if (v = "")
        return ""
    if (SubStr(v, 1, 1) != ".")
        v := "." v
    return v
}

; Normalizes path for prefix checks.
ScriptRunnerNormalizePath(path) {
    normalized := StrReplace(path, "/", "\")
    normalized := RegExReplace(normalized, "\\+$")
    return normalized
}

; Returns a safely quoted command-line argument string.
ScriptRunnerQuoteArg(value) {
    return '"' StrReplace(value, '"', '\"') '"'
}

; Sort callback for script menu display names.
ScriptRunnerCompareItemsByName(a, b, *) {
    aa := StrLower(a.name)
    bb := StrLower(b.name)
    if (aa = bb)
        return 0
    return (aa < bb) ? -1 : 1
}

; No-op callback for disabled info menu rows.
ScriptRunnerNoOp(*) {
}
