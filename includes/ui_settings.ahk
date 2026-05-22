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
    global StorageMode, DataRootDir
    global _ScriptRunnerState

    ScriptRunnerInitDefaults()

    if IsObject(_SettingsWindowState) {
        try {
            _SettingsWindowState.gui.Show()
            _SettingsWindowState.gui.Focus()
            return
        }
    }

    sGui := Gui("+Resize +MinSize560x470", T("settings_window_title"))
    sGui.SetFont("s10", "Segoe UI")

    sGui.AddGroupBox("x10 y10 w540 h128", T("settings_storage"))
    providerText := sGui.AddText("x24 y32 w510", T("msg_storage_provider") ": " GetProviderDisplayName())
    pathText := sGui.AddText("x24 y54 w510", T("msg_storage_path") ": " DataRootDir)
    sGui.AddText("x24 y80 w110 h20", T("settings_storage_type"))
    storageDDL := sGui.AddDropDownList("x140 y78 w280", GetStorageModeChoices())
    storageDDL.Choose(StorageModeToChoiceIndex(StorageMode))
    btnMigrate := sGui.AddButton("x430 y76 w90 h24", T("settings_migrate"))
    btnMigrate.Enabled := false

    sGui.AddGroupBox("x10 y146 w540 h90", T("settings_hotkey"))
    hotkeyEdit := sGui.AddText("x24 y170 w380 h24 +Border", HotkeyToDisplay(ConfiguredHotkey))
    btnHotkey := sGui.AddButton("x412 y168 w120 h26", T("menu_configure_hotkey"))

    sGui.AddGroupBox("x10 y244 w540 h80", T("settings_language"))
    langDDL := sGui.AddDropDownList("x24 y270 w180 Choose1", [T("menu_language_en"), T("menu_language_sv")])
    if (AppLanguage = "sv")
        langDDL.Choose(2)
    chkBeta := sGui.AddCheckbox("x240 y272 w280", CheckBetaReleases ? T("toggle_beta_on") : T("toggle_beta_off"))
    chkBeta.Value := CheckBetaReleases ? 1 : 0

    sGui.AddGroupBox("x10 y330 w540 h96", T("settings_scripts"))
    chkScriptRunner := sGui.AddCheckbox("x24 y352 w200", T("settings_scripts_enable"))
    chkScriptRunner.Value := _ScriptRunnerState.enabled ? 1 : 0
    btnScriptConfigure := sGui.AddButton("x420 y350 w112 h24", T("settings_scripts_configure"))
    sGui.AddText("x24 y380 w98 h20", T("settings_scripts_folder"))
    scriptFolderEdit := sGui.AddEdit("x128 y378 w286 h24", _ScriptRunnerState.folder)
    btnScriptBrowse := sGui.AddButton("x420 y378 w58 h24", T("settings_scripts_browse"))
    btnScriptRefresh := sGui.AddButton("x482 y378 w50 h24", T("settings_scripts_refresh"))

    btnStorage := sGui.AddButton("x10 y436 w90 h30", T("menu_show_storage"))
    btnValidate := sGui.AddButton("x108 y436 w90 h30", T("settings_validate"))
    btnRestore := sGui.AddButton("x206 y436 w90 h30", T("settings_restore"))
    btnUndo := sGui.AddButton("x304 y436 w80 h30", T("settings_undo"))
    btnUpdates := sGui.AddButton("x392 y436 w90 h30", T("settings_updates"))
    btnClose := sGui.AddButton("x490 y436 w60 h30", T("settings_close"))
    btnRestore.Enabled := false
    btnUndo.Enabled := false

    state := {
        gui: sGui,
        dataRootDir: DataRootDir,
        providerText: providerText,
        pathText: pathText,
        hotkeyEdit: hotkeyEdit,
        storageDDL: storageDDL,
        btnMigrate: btnMigrate,
        langDDL: langDDL,
        chkBeta: chkBeta,
        chkScriptRunner: chkScriptRunner,
        btnScriptConfigure: btnScriptConfigure,
        scriptFolderEdit: scriptFolderEdit,
        btnScriptBrowse: btnScriptBrowse,
        btnScriptRefresh: btnScriptRefresh,
        btnRestore: btnRestore,
        btnUndo: btnUndo
    }
    _SettingsWindowState := state

    btnHotkey.OnEvent("Click", SettingsOpenHotkeyDialog.Bind(state))
    storageDDL.OnEvent("Change", SettingsWindowStorageSelectionChanged.Bind(state))
    btnMigrate.OnEvent("Click", SettingsWindowMigrateStorage.Bind(state))
    langDDL.OnEvent("Change", SettingsWindowLanguageChanged.Bind(state))
    chkBeta.OnEvent("Click", SettingsWindowBetaChanged.Bind(state))
    chkScriptRunner.OnEvent("Click", SettingsWindowScriptRunnerEnabledChanged.Bind(state))
    btnScriptConfigure.OnEvent("Click", SettingsWindowScriptRunnerConfigure.Bind(state))
    scriptFolderEdit.OnEvent("LoseFocus", SettingsWindowScriptRunnerFolderEdited.Bind(state))
    btnScriptBrowse.OnEvent("Click", SettingsWindowScriptRunnerBrowseFolder.Bind(state))
    btnScriptRefresh.OnEvent("Click", SettingsWindowScriptRunnerRefresh.Bind(state))
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
    sGui.Show("w560 h474")
}

; Sets or applies settings open hotkey dialog.
SettingsOpenHotkeyDialog(state, *) {
    OpenHotkeyConfigDialog(false)
    state.hotkeyEdit.Text := HotkeyToDisplay(ConfiguredHotkey)
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

; Updates settings script runner control enablement.
UpdateScriptRunnerControlsState(state) {
    if !IsObject(state)
        return
    if !state.HasOwnProp("chkScriptRunner")
        return

    enabled := (state.chkScriptRunner.Value = 1)
    state.btnScriptConfigure.Enabled := enabled
    state.scriptFolderEdit.Enabled := enabled
    state.btnScriptBrowse.Enabled := enabled
    state.btnScriptRefresh.Enabled := enabled
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
