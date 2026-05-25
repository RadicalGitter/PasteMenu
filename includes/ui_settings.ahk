; ---------------------------------------------------------------------
; Settings module:
; - Settings window rendering and event wiring
; - Storage migration controls
; - Backup restore/undo controls
; ---------------------------------------------------------------------

; Opens the hotkey configuration dialog from settings.
SettingsConfigureHotkeyAction(*) {
    OpenHotkeyConfigDialog(false)
}

; Opens or shows open settings window.
OpenSettingsWindow(*) {
    global _SettingsWindowState, AppLanguage, CheckBetaReleases, ConfiguredHotkey
    global StorageMode, DataRootDir, HotwheelHoldThresholdMs
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()

    if IsObject(_SettingsWindowState) {
        try {
            _SettingsWindowState.gui.Show()
            _SettingsWindowState.gui.Focus()
            return
        }
    }

    sGui := Gui("+Resize +MinSize620x520", T("settings_window_title"))
    sGui.SetFont("s10", "Segoe UI")

    tabs := sGui.AddTab3("x10 y10 w600 h430", [T("settings_tab_texts"), T("settings_tab_scripts")])

    tabs.UseTab(1)
    sGui.AddGroupBox("x24 y50 w572 h128", T("settings_storage"))
    providerText := sGui.AddText("x38 y72 w540", T("msg_storage_provider") ": " GetProviderDisplayName())
    pathText := sGui.AddText("x38 y94 w540", T("msg_storage_path") ": " DataRootDir)
    sGui.AddText("x38 y120 w110 h20", T("settings_storage_type"))
    storageDDL := sGui.AddDropDownList("x154 y118 w300", GetStorageModeChoices())
    storageDDL.Choose(StorageModeToChoiceIndex(StorageMode))
    btnMigrate := sGui.AddButton("x464 y116 w100 h24", T("settings_migrate"))
    btnMigrate.Enabled := false

    sGui.AddGroupBox("x24 y188 w572 h80", T("settings_hotkey"))
    hotkeyEdit := sGui.AddText("x38 y216 w390 h24 +Border", HotkeyToDisplay(ConfiguredHotkey))
    btnHotkey := sGui.AddButton("x438 y214 w126 h26", T("menu_configure_hotkey"))
    sGui.AddText("x38 y246 w130 h20", T("settings_hotwheel_hold_ms"))
    thresholdEdit := sGui.AddEdit("x174 y244 w70 h24 Number", NormalizeHotwheelHoldThresholdMs(HotwheelHoldThresholdMs) "")

    sGui.AddGroupBox("x24 y278 w572 h80", T("settings_language"))
    langDDL := sGui.AddDropDownList("x38 y306 w190 Choose1", [T("menu_language_en"), T("menu_language_sv")])
    if (AppLanguage = "sv")
        langDDL.Choose(2)
    chkBeta := sGui.AddCheckbox("x250 y308 w310", CheckBetaReleases ? T("toggle_beta_on") : T("toggle_beta_off"))
    chkBeta.Value := CheckBetaReleases ? 1 : 0

    tabs.UseTab(2)
    chkScriptRunner := sGui.AddCheckbox("x32 y52 w260 h24", T("settings_scripts_enable"))
    chkScriptRunner.Value := _ScriptRunnerState.enabled ? 1 : 0

    lblScriptFolder := sGui.AddText("x32 y92 w110 h20", T("settings_scripts_folder"))
    scriptFolderEdit := sGui.AddEdit("x150 y90 w310 h24", _ScriptRunnerState.folder)
    btnScriptBrowse := sGui.AddButton("x468 y90 w62 h24", T("settings_scripts_browse"))
    btnScriptRefresh := sGui.AddButton("x536 y90 w54 h24", T("settings_scripts_refresh"))

    chkScriptRecursive := sGui.AddCheckbox("x32 y132 w220 h24", T("settings_scripts_recursive"))
    chkScriptRecursive.Value := _ScriptRunnerState.recursive ? 1 : 0
    chkScriptRequireConfirm := sGui.AddCheckbox("x300 y132 w260 h24", T("settings_scripts_require_confirm"))
    chkScriptRequireConfirm.Value := _ScriptRunnerState.requireConfirm ? 1 : 0
    chkScriptShowConsole := sGui.AddCheckbox("x32 y162 w220 h24", T("settings_scripts_show_console"))
    chkScriptShowConsole.Value := _ScriptRunnerState.showConsole ? 1 : 0
    chkScriptWaitForExit := sGui.AddCheckbox("x300 y162 w260 h24", T("settings_scripts_wait_for_exit"))
    chkScriptWaitForExit.Value := _ScriptRunnerState.waitForExit ? 1 : 0

    lblScriptMaxItems := sGui.AddText("x32 y202 w110 h20", T("settings_scripts_max_items"))
    scriptMaxItemsEdit := sGui.AddEdit("x150 y200 w70 h24 Number", _ScriptRunnerState.maxItems "")

    btnScriptConfigure := sGui.AddButton("x32 y242 w150 h26", T("settings_scripts_configure"))
    btnScriptOpenFolder := sGui.AddButton("x194 y242 w150 h26", T("menu_run_script_open_folder"))

    tabs.UseTab()

    btnStorage := sGui.AddButton("x10 y455 w90 h30", T("menu_show_storage"))
    btnValidate := sGui.AddButton("x108 y455 w100 h30", T("settings_validate"))
    btnRestore := sGui.AddButton("x216 y455 w100 h30", T("settings_restore"))
    btnUndo := sGui.AddButton("x324 y455 w80 h30", T("settings_undo"))
    btnUpdates := sGui.AddButton("x412 y455 w112 h30", T("settings_updates"))
    btnClose := sGui.AddButton("x550 y455 w60 h30", T("settings_close"))
    btnRestore.Enabled := false
    btnUndo.Enabled := false

    state := {
        gui: sGui,
        dataRootDir: DataRootDir,
        providerText: providerText,
        pathText: pathText,
        hotkeyEdit: hotkeyEdit,
        thresholdEdit: thresholdEdit,
        storageDDL: storageDDL,
        btnMigrate: btnMigrate,
        langDDL: langDDL,
        chkBeta: chkBeta,
        chkScriptRunner: chkScriptRunner,
        lblScriptFolder: lblScriptFolder,
        btnScriptConfigure: btnScriptConfigure,
        btnScriptOpenFolder: btnScriptOpenFolder,
        scriptFolderEdit: scriptFolderEdit,
        btnScriptBrowse: btnScriptBrowse,
        btnScriptRefresh: btnScriptRefresh,
        chkScriptRecursive: chkScriptRecursive,
        chkScriptRequireConfirm: chkScriptRequireConfirm,
        chkScriptShowConsole: chkScriptShowConsole,
        chkScriptWaitForExit: chkScriptWaitForExit,
        lblScriptMaxItems: lblScriptMaxItems,
        scriptMaxItemsEdit: scriptMaxItemsEdit,
        btnRestore: btnRestore,
        btnUndo: btnUndo
    }
    _SettingsWindowState := state

    btnHotkey.OnEvent("Click", SettingsOpenHotkeyDialog.Bind(state))
    thresholdEdit.OnEvent("LoseFocus", SettingsWindowHotwheelThresholdEdited.Bind(state))
    storageDDL.OnEvent("Change", SettingsWindowStorageSelectionChanged.Bind(state))
    btnMigrate.OnEvent("Click", SettingsWindowMigrateStorage.Bind(state))
    langDDL.OnEvent("Change", SettingsWindowLanguageChanged.Bind(state))
    chkBeta.OnEvent("Click", SettingsWindowBetaChanged.Bind(state))
    chkScriptRunner.OnEvent("Click", SettingsWindowScriptRunnerEnabledChanged.Bind(state))
    btnScriptConfigure.OnEvent("Click", SettingsWindowScriptRunnerConfigure.Bind(state))
    btnScriptOpenFolder.OnEvent("Click", SettingsWindowScriptRunnerOpenFolder.Bind(state))
    scriptFolderEdit.OnEvent("LoseFocus", SettingsWindowScriptRunnerFolderEdited.Bind(state))
    btnScriptBrowse.OnEvent("Click", SettingsWindowScriptRunnerBrowseFolder.Bind(state))
    btnScriptRefresh.OnEvent("Click", SettingsWindowScriptRunnerRefresh.Bind(state))
    chkScriptRecursive.OnEvent("Click", SettingsWindowScriptRunnerOptionChanged.Bind(state, "recursive"))
    chkScriptRequireConfirm.OnEvent("Click", SettingsWindowScriptRunnerOptionChanged.Bind(state, "requireConfirm"))
    chkScriptShowConsole.OnEvent("Click", SettingsWindowScriptRunnerOptionChanged.Bind(state, "showConsole"))
    chkScriptWaitForExit.OnEvent("Click", SettingsWindowScriptRunnerOptionChanged.Bind(state, "waitForExit"))
    scriptMaxItemsEdit.OnEvent("LoseFocus", SettingsWindowScriptRunnerMaxItemsEdited.Bind(state))
    btnStorage.OnEvent("Click", SettingsOpenStorageFromState.Bind(state))
    btnValidate.OnEvent("Click", SettingsValidateFixNowAction)
    btnRestore.OnEvent("Click", SettingsRestoreBackupAction.Bind(state))
    btnUndo.OnEvent("Click", SettingsUndoLastRestoreAction.Bind(state))
    btnUpdates.OnEvent("Click", SettingsCheckUpdatesAction)
    btnClose.OnEvent("Click", SettingsWindowClose.Bind(state))
    sGui.OnEvent("Close", SettingsWindowClose.Bind(state))
    sGui.OnEvent("Escape", SettingsWindowClose.Bind(state))

    UpdateStorageMigrateButtonState(state)
    UpdateRestoreBackupButtonState(state)
    UpdateUndoButtonState(state)
    UpdateScriptRunnerControlsState(state)
    sGui.Show("w620 h500")
}

; Sets or applies settings open hotkey dialog.
SettingsOpenHotkeyDialog(state, *) {
    OpenHotkeyConfigDialog(false)
    state.hotkeyEdit.Text := HotkeyToDisplay(ConfiguredHotkey)
}

SettingsWindowHotwheelThresholdEdited(state, ctrl, *) {
    global HotwheelHoldThresholdMs
    HotwheelHoldThresholdMs := NormalizeHotwheelHoldThresholdMs(ctrl.Value)
    ctrl.Value := HotwheelHoldThresholdMs ""
    SaveSettings()
}

; Sets or applies settings window language changed.
SettingsWindowLanguageChanged(state, ctrl, *) {
    choice := ctrl.Text
    if (choice = T("menu_language_sv"))
        SettingsSetLanguageAction("sv")
    else
        SettingsSetLanguageAction("en")

    ; Reopen settings UI to refresh localized labels.
    try state.gui.Destroy()
    global _SettingsWindowState
    _SettingsWindowState := 0
    OpenSettingsWindow()
}

; Sets or applies settings window beta changed.
SettingsWindowBetaChanged(state, ctrl, *) {
    global CheckBetaReleases
    CheckBetaReleases := (ctrl.Value = 1)
    SaveSettings()
    ctrl.Text := CheckBetaReleases ? T("toggle_beta_on") : T("toggle_beta_off")
}

; Sets or applies settings window script runner enabled changed.
SettingsWindowScriptRunnerEnabledChanged(state, ctrl, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    _ScriptRunnerState.enabled := (ctrl.Value = 1)
    SaveSettings()
    ScriptRunnerRefreshCache(true)
    UpdateScriptRunnerControlsState(state)
}

; Sets or applies settings window script runner configure mappings.
SettingsWindowScriptRunnerConfigure(state, *) {
    OpenScriptRunnerMappingDialog()
}

; Opens configured scripts folder from settings.
SettingsWindowScriptRunnerOpenFolder(state, *) {
    ScriptRunnerOpenFolderAction()
}

; Sets or applies settings window script runner folder edited.
SettingsWindowScriptRunnerFolderEdited(state, ctrl, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    ScriptRunnerSetFolder(ctrl.Value)
    state.scriptFolderEdit.Value := _ScriptRunnerState.folder
    SaveSettings()
    ScriptRunnerRefreshCache(true)
}

; Sets or applies settings window script runner browse folder.
SettingsWindowScriptRunnerBrowseFolder(state, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    startDir := _ScriptRunnerState.folder
    if (startDir = "" || !DirExist(startDir))
        startDir := A_MyDocuments

    selected := DirSelect(startDir, 3, T("settings_scripts_folder"))
    if (selected = "")
        return

    ScriptRunnerSetFolder(selected)
    state.scriptFolderEdit.Value := _ScriptRunnerState.folder
    SaveSettings()
    ScriptRunnerRefreshCache(true)
}

; Sets or applies settings window script runner refresh.
SettingsWindowScriptRunnerRefresh(state, *) {
    global _ScriptRunnerState

    items := ScriptRunnerRefreshCache(true)
    if (_ScriptRunnerState.lastError != "") {
        ShowTransientToolTip(_ScriptRunnerState.lastError)
        return
    }

    ShowTransientToolTip(T("settings_scripts_refresh") ": " items.Length)
}

; Sets or applies one script runner boolean option.
SettingsWindowScriptRunnerOptionChanged(state, key, ctrl, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    value := (ctrl.Value = 1)
    switch key {
        case "recursive":
            _ScriptRunnerState.recursive := value
            ScriptRunnerRefreshCache(true)
        case "requireConfirm":
            _ScriptRunnerState.requireConfirm := value
        case "showConsole":
            _ScriptRunnerState.showConsole := value
        case "waitForExit":
            _ScriptRunnerState.waitForExit := value
    }
    SaveSettings()
}

; Sets or applies script runner maximum menu item count.
SettingsWindowScriptRunnerMaxItemsEdited(state, ctrl, *) {
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()
    raw := Trim(ctrl.Value)
    if RegExMatch(raw, "^-?\d+$")
        value := raw + 0
    else
        value := _ScriptRunnerState.maxItems

    if (value < 1)
        value := 1
    if (value > 300)
        value := 300

    _ScriptRunnerState.maxItems := value
    ctrl.Value := value ""
    SaveSettings()
    ScriptRunnerRefreshCache(true)
}

; Updates settings script runner control enablement.
UpdateScriptRunnerControlsState(state) {
    if !IsObject(state)
        return
    if !state.HasOwnProp("chkScriptRunner")
        return

    enabled := (state.chkScriptRunner.Value = 1)
    controls := [
        "lblScriptFolder",
        "scriptFolderEdit",
        "btnScriptBrowse",
        "btnScriptRefresh",
        "chkScriptRecursive",
        "chkScriptRequireConfirm",
        "chkScriptShowConsole",
        "chkScriptWaitForExit",
        "lblScriptMaxItems",
        "scriptMaxItemsEdit",
        "btnScriptConfigure",
        "btnScriptOpenFolder"
    ]
    for _, prop in controls {
        if state.HasOwnProp(prop)
            state.%prop%.Enabled := enabled
    }
}

; Updates update storage migrate button state.
UpdateStorageMigrateButtonState(state) {
    global StorageMode
    chosenMode := StorageModeFromChoiceIndex(state.storageDDL.Value)
    state.btnMigrate.Enabled := (chosenMode != StorageMode)
}

; Updates update restore backup button state.
UpdateRestoreBackupButtonState(state) {
    if !IsObject(state)
        return
    if !state.HasOwnProp("btnRestore")
        return
    state.btnRestore.Enabled := (GetAvailableBackups().Length > 0)
}

; Updates update undo button state.
UpdateUndoButtonState(state) {
    global _UndoState
    if !IsObject(state)
        return
    if !state.HasOwnProp("btnUndo")
        return
    state.btnUndo.Enabled := IsObject(_UndoState)
}

; Sets or applies settings window storage selection changed.
SettingsWindowStorageSelectionChanged(state, ctrl, *) {
    UpdateStorageMigrateButtonState(state)
}

; Sets or applies settings window migrate storage.
SettingsWindowMigrateStorage(state, *) {
    global StorageMode, SnippetFile, SettingsFile, DataRootDir, SnippetEncoding

    chosenMode := StorageModeFromChoiceIndex(state.storageDDL.Value)
    if (chosenMode = StorageMode) {
        UpdateStorageMigrateButtonState(state)
        return
    }

    sourceMode := StorageMode
    sourceSnippet := SnippetFile
    sourceSettings := SettingsFile

    targetRoot := ResolveStorageRootStrict(chosenMode)
    if (targetRoot = "") {
        reason := T("msg_migrate_failed") "`n`n" T("msg_storage_provider") ": " chosenMode
        MsgBox reason, T("settings_window_title")
        return
    }

    targetSnippet := targetRoot "\pastemenu.txt"
    targetSettings := targetRoot "\settings.ini"
    sourceSnippet := SelectSourceSnippetForMigration(sourceSnippet, targetSnippet)
    sourceSettings := SelectSourceSettingsForMigration(sourceSettings, targetSettings)

    ok := true
    if (sourceSnippet != "") {
        if !CopySnippetWithFallback(sourceSnippet, targetSnippet, SnippetEncoding)
            ok := false
        else if !FileExist(targetSnippet)
            ok := false
        else if !PathsEqual(sourceSnippet, targetSnippet) {
            MoveSnippetCompanionFiles(sourceSnippet, targetSnippet)
            try FileDelete(sourceSnippet)
        }
    } else {
        EnsureSnippetFile(targetSnippet)
        if !FileExist(targetSnippet)
            ok := false
    }

    if ok && (sourceSettings != "") {
        if !CopySettingsWithFallback(sourceSettings, targetSettings)
            ok := false
        else if !FileExist(targetSettings)
            ok := false
        else if !PathsEqual(sourceSettings, targetSettings)
            try FileDelete(sourceSettings)
    }

    if !ok {
        StorageMode := sourceMode
        ApplyStorageSelection()
        state.storageDDL.Choose(StorageModeToChoiceIndex(StorageMode))
        UpdateStorageMigrateButtonState(state)
        MsgBox T("msg_migrate_failed"), T("settings_window_title")
        return
    }

    StorageMode := chosenMode
    ApplyStorageSelection()
    EnsureSnippetFile(targetSnippet)
    SaveSettings()
    state.dataRootDir := DataRootDir
    state.providerText.Text := T("msg_storage_provider") ": " GetProviderDisplayName()
    state.pathText.Text := T("msg_storage_path") ": " DataRootDir
    state.storageDDL.Choose(StorageModeToChoiceIndex(StorageMode))
    UpdateStorageMigrateButtonState(state)
    UpdateRestoreBackupButtonState(state)
    UpdateUndoButtonState(state)
    MsgBox T("msg_migrate_done"), T("settings_window_title")
}

; Sets or applies settings open storage from state.
SettingsOpenStorageFromState(state, *) {
    path := state.dataRootDir
    if (path = "")
        path := DataRootDir
    SettingsShowStorageLocationAction(path)
}

; Sets or applies settings restore backup action.
SettingsRestoreBackupAction(state, *) {
    global SnippetFile, SnippetEncoding

    ; Refresh candidates each open so consumed change items disappear immediately.
    backups := GetAvailableBackups()
    if (backups.Length = 0) {
        ShowTransientToolTip(T("msg_no_backups"))
        UpdateRestoreBackupButtonState(state)
        return
    }

    idx := PromptSelectBackupIndex(backups)
    if (idx < 1 || idx > backups.Length)
        return
    backup := backups[idx]

    ans := MsgBox(T("msg_restore_confirm"), T("restore_window_title"), "YesNo Icon?")
    if (ans != "Yes")
        return

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }

    currentText := ReadTextFile(SnippetFile, SnippetEncoding)
    if (currentText != "")
        CreateTieredSnippetBackups(SnippetFile, currentText, SnippetEncoding, 0, false)

    if (backup.tier = "change" && backup.isChange) {
        ; Per-change restore reverts one entry mutation, not the full file.
        backupRaw := ReadTextFile(backup.path, "UTF-8")
        if (backupRaw = "") {
            MsgBox T("msg_restore_failed"), T("restore_window_title")
            return
        }

        ApplyBeforeStateFromChange(backup.change)
        if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, 0, false) {
            MsgBox T("msg_restore_failed"), T("restore_window_title")
            return
        }

        ; Consume the restored change to prevent accidental duplicate restores.
        try FileDelete(backup.path)
        SetUndoState({
            kind: "change_restore",
            backupPath: backup.path,
            backupRaw: backupRaw,
            change: backup.change
        })

        RefreshEditorAfterExternalDataChange()
        UpdateRestoreBackupButtonState(state)
        UpdateUndoButtonState(state)
        MsgBox T("msg_restore_done"), T("restore_window_title")
        return
    }

    restoredText := ReadTextFile(backup.path, SnippetEncoding)
    if (restoredText = "") {
        MsgBox T("msg_restore_failed"), T("restore_window_title")
        return
    }

    if !WriteTextFileAtomic(SnippetFile, restoredText, SnippetEncoding) {
        MsgBox T("msg_restore_failed"), T("restore_window_title")
        return
    }

    CreateTieredSnippetBackups(SnippetFile, restoredText, SnippetEncoding, 0, false)
    SetUndoState({
        kind: "full_restore",
        previousText: currentText
    })

    RefreshEditorAfterExternalDataChange()
    UpdateRestoreBackupButtonState(state)
    UpdateUndoButtonState(state)
    MsgBox T("msg_restore_done"), T("restore_window_title")
}

; Sets or applies settings undo last restore action.
SettingsUndoLastRestoreAction(state, *) {
    global _UndoState, SnippetFile, SnippetEncoding

    if !IsObject(_UndoState) {
        ShowTransientToolTip(T("msg_undo_none"))
        UpdateUndoButtonState(state)
        return
    }

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }

    ok := false
    if (_UndoState.kind = "full_restore") {
        ; Undo a full restore by writing back the captured previous snapshot.
        currentText := ReadTextFile(SnippetFile, SnippetEncoding)
        if (currentText != "")
            CreateTieredSnippetBackups(SnippetFile, currentText, SnippetEncoding, 0, false)

        if WriteTextFileAtomic(SnippetFile, _UndoState.previousText, SnippetEncoding) {
            CreateTieredSnippetBackups(SnippetFile, _UndoState.previousText, SnippetEncoding, 0, false)
            ok := true
        }
    } else if (_UndoState.kind = "change_restore") {
        ; Undo a per-change restore by applying the original post-change state.
        change := _UndoState.change
        ApplyAfterStateFromChange(change)
        if SaveSnippetsToFile(SnippetFile, SnippetEncoding, 0, false) {
            if (_UndoState.backupPath != "" && _UndoState.backupRaw != "")
                WriteTextFileAtomic(_UndoState.backupPath, _UndoState.backupRaw, "UTF-8")
            ok := true
        }
    }

    if !ok {
        MsgBox T("msg_undo_failed"), T("restore_window_title")
        return
    }

    ClearUndoState()
    RefreshEditorAfterExternalDataChange()
    UpdateRestoreBackupButtonState(state)
    UpdateUndoButtonState(state)
    MsgBox T("msg_undo_done"), T("restore_window_title")
}

; Sets or applies set undo state.
SetUndoState(undoState) {
    global _UndoState, _SettingsWindowState
    _UndoState := undoState
    if IsObject(_SettingsWindowState)
        UpdateUndoButtonState(_SettingsWindowState)
}

; Deletes or removes clear undo state.
ClearUndoState() {
    global _UndoState, _SettingsWindowState
    _UndoState := 0
    if IsObject(_SettingsWindowState)
        UpdateUndoButtonState(_SettingsWindowState)
}

; Updates refresh editor after external data change.
RefreshEditorAfterExternalDataChange() {
    global _EditorState, _Categories, _EntriesByCategory, _EntryOrderByCategory

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return false
    }

    if IsObject(_EditorState) {
        targetCategory := _EditorState.currentCategory
        targetTitle := _EditorState.currentTitle
        if !_EntryOrderByCategory.Has(targetCategory) {
            targetCategory := (_Categories.Length > 0) ? _Categories[1] : ""
            targetTitle := ""
        }
        if (targetCategory != "") {
            startNew := (_EntryOrderByCategory[targetCategory].Length = 0)
            if !startNew && (targetTitle != "") && !_EntriesByCategory[targetCategory].Has(targetTitle)
                targetTitle := ""
            EditorLoadCategory(_EditorState, targetCategory, targetTitle, startNew)
        }
    }
    return true
}

; Creates or builds ensure global category.
EnsureGlobalCategory(category) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    if (category = "")
        return
    if _EntriesByCategory.Has(category)
        return
    _Categories.Push(category)
    _EntriesByCategory[category] := Map()
    _EntryOrderByCategory[category] := []
}

; Deletes or removes remove global entry.
RemoveGlobalEntry(category, title) {
    global _EntriesByCategory, _EntryOrderByCategory
    if (category = "" || title = "")
        return
    if !_EntriesByCategory.Has(category)
        return
    entries := _EntriesByCategory[category]
    order := _EntryOrderByCategory[category]
    if entries.Has(title)
        entries.Delete(title)
    idx := FindIndexInArray(order, title)
    if idx
        order.RemoveAt(idx)
}

; Sets or applies set global entry.
SetGlobalEntry(category, title, content) {
    global _EntriesByCategory, _EntryOrderByCategory
    if (category = "" || title = "")
        return
    EnsureGlobalCategory(category)
    entries := _EntriesByCategory[category]
    order := _EntryOrderByCategory[category]
    if !entries.Has(title)
        order.Push(title)
    entries[title] := content
}

; Sets or applies apply before state from change.
ApplyBeforeStateFromChange(change) {
    if !IsObject(change)
        return

    diffLocation := (change.beforeCategory != change.afterCategory || change.beforeTitle != change.afterTitle)
    if (diffLocation && change.afterExists)
        RemoveGlobalEntry(change.afterCategory, change.afterTitle)

    if change.beforeExists
        SetGlobalEntry(change.beforeCategory, change.beforeTitle, change.beforeText)
    else
        RemoveGlobalEntry(change.beforeCategory, change.beforeTitle)
}

; Sets or applies apply after state from change.
ApplyAfterStateFromChange(change) {
    if !IsObject(change)
        return

    diffLocation := (change.beforeCategory != change.afterCategory || change.beforeTitle != change.afterTitle)
    if (diffLocation && change.beforeExists)
        RemoveGlobalEntry(change.beforeCategory, change.beforeTitle)

    if change.afterExists
        SetGlobalEntry(change.afterCategory, change.afterTitle, change.afterText)
    else
        RemoveGlobalEntry(change.afterCategory, change.afterTitle)
}

; Sets or applies settings window close.
SettingsWindowClose(state, *) {
    global _SettingsWindowState
    try state.gui.Destroy()
    _SettingsWindowState := 0
}

; Sets or applies settings show storage location action.
SettingsShowStorageLocationAction(path := "") {
    global DataRootDir
    targetPath := path
    if (targetPath = "")
        targetPath := DataRootDir
    try {
        if !DirExist(targetPath)
            DirCreate(targetPath)
        Run('explorer.exe "' targetPath '"')
        return
    } catch {
        msg := T("msg_storage_provider") ": " GetProviderDisplayName() "`n"
        msg .= T("msg_storage_path") ": " targetPath
        MsgBox msg, T("msg_storage_title")
    }
}

; Sets or applies settings validate fix now action.
SettingsValidateFixNowAction(*) {
    global SnippetFile, SnippetEncoding, DefaultCategory
    message := ValidateAndFixSnippetFile(SnippetFile, SnippetEncoding, DefaultCategory, true)
    MsgBox message, T("menu_settings")
}

; Sets or applies settings set language action.
SettingsSetLanguageAction(lang, *) {
    global AppLanguage, _SettingsWindowState, ConfiguredHotkey
    AppLanguage := lang
    SaveSettings()
    if IsObject(_SettingsWindowState)
        try _SettingsWindowState.hotkeyEdit.Text := HotkeyToDisplay(ConfiguredHotkey)
    SetupTrayMenu()
    MsgBox T("msg_settings_saved"), T("menu_settings")
}

; Sets or applies settings toggle beta releases action.
SettingsToggleBetaReleasesAction(*) {
    global CheckBetaReleases
    CheckBetaReleases := !CheckBetaReleases
    SaveSettings()
}

; Sets or applies settings check updates action.
SettingsCheckUpdatesAction(*) {
    global CheckBetaReleases
    ; Placeholder until standalone .exe release flow is in place.
    mode := CheckBetaReleases ? T("updates_mode_beta") : T("updates_mode_stable")
    msg := T("msg_updates_placeholder") "`n`n" T("updates_mode_label") ": " mode
    MsgBox msg, T("msg_updates_placeholder_title")
}

; Handles paths equal.
PathsEqual(pathA, pathB) {
    return (StrLower(NormalizePath(pathA)) = StrLower(NormalizePath(pathB)))
}

; Handles normalize path.
NormalizePath(path) {
    normalizedPath := StrReplace(path, "/", "\")
    normalizedPath := RegExReplace(normalizedPath, "\\+$")
    return normalizedPath
}

; Handles safe file get time.
SafeFileGetTime(path) {
    try return FileGetTime(path, "M")
    return ""
}

; Handles safe file get size.
SafeFileGetSize(path) {
    try return FileGetSize(path)
    return -1
}

; Handles check script dir snippet override.
CheckScriptDirSnippetOverride() {
    global SnippetFile, SnippetEncoding

    localSnippetPath := A_ScriptDir "\pastemenu.txt"
    if !FileExist(localSnippetPath)
        return false
    if PathsEqual(localSnippetPath, SnippetFile)
        return false

    persistentExists := FileExist(SnippetFile)
    isNewer := false
    isLarger := false
    shouldPrompt := false

    if !persistentExists {
        shouldPrompt := true
    } else {
        localTime := SafeFileGetTime(localSnippetPath)
        persistentTime := SafeFileGetTime(SnippetFile)
        localSize := SafeFileGetSize(localSnippetPath)
        persistentSize := SafeFileGetSize(SnippetFile)

        isNewer := (localTime != "" && persistentTime != "" && localTime > persistentTime)
        isLarger := (localSize >= 0 && persistentSize >= 0 && localSize > persistentSize)
        shouldPrompt := (isNewer || isLarger)
    }

    if !shouldPrompt
        return false

    reasonText := ""
    if (isNewer && isLarger)
        reasonText := T("msg_sync_reason_newer_larger")
    else if isNewer
        reasonText := T("msg_sync_reason_newer")
    else if isLarger
        reasonText := T("msg_sync_reason_larger")
    else
        reasonText := T("msg_sync_reason_missing")

    prompt := T("msg_sync_prompt")
    prompt .= "`n`n" reasonText
    prompt .= "`n`n" T("msg_sync_source") ":`n" localSnippetPath
    prompt .= "`n`n" T("msg_sync_target") ":`n" SnippetFile

    ans := MsgBox(prompt, T("msg_sync_title"), "YesNo Icon?")
    if (ans != "Yes")
        return false

    text := ReadTextFile(localSnippetPath, SnippetEncoding)
    if (text = "") {
        MsgBox T("msg_sync_failed"), T("msg_sync_title")
        return false
    }

    if !WriteTextFileAtomic(SnippetFile, text, SnippetEncoding) {
        MsgBox T("msg_sync_failed"), T("msg_sync_title")
        return false
    }

    MsgBox T("msg_sync_done"), T("msg_sync_title")
    return true
}

; Initializes or controls init on startup.
