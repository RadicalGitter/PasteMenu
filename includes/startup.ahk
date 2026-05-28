InitOnStartup() {
    global SnippetFile, SnippetEncoding, DefaultCategory, SettingsFile, ConfiguredHotkey, StorageMode

    LoadStorageMode()
    ApplyStorageSelection()
    firstRun := !FileExist(SettingsFile)
    LoadSettings()
    ScriptRunnerRefreshCache(true)
    LLMCallsEnsurePromptFile()
    LLMExamplesLoad()

    MaybeOfferAppDataToDropboxMigration()

    ; Migration flow may update StorageMode/SnippetFile.
    ApplyStorageSelection()
    LLMCallsEnsurePromptFile()
    LLMExamplesLoad()

    if (firstRun) {
        MsgBox T("msg_hotkey_firstrun_prompt"), T("msg_hotkey_firstrun_title")
        OpenHotkeyConfigDialog(true)
    }

    if (ConfiguredHotkey = "")
        ConfiguredHotkey := "^F9"
    if !RegisterConfiguredHotkey()
        MsgBox T("msg_hotkey_invalid"), T("msg_fix_title")

    SaveSettings()
    SetupTrayMenu()

    fileExisted := FileExist(SnippetFile)
    EnsureSnippetFile(SnippetFile)
    importedFromLocal := CheckScriptDirSnippetOverride()

    ; On existing files: validate silently and only prompt if issues are found.
    if (fileExisted || importedFromLocal) {
        result := ValidateAndFixSnippetFile(SnippetFile, SnippetEncoding, DefaultCategory, true)
        ; Only surface operational failures automatically.
        if InStr(result, "failed")
            MsgBox result, "PasteMenu v3"
    }
}

; Handles validate and fix snippet file.
