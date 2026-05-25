ResolveDataRootDir(storageMode := "auto") {
    global DataRootProvider
    global UseCloudPortableStorage
    baseName := "PasteMenu"

    mode := StrLower(Trim(storageMode))

    if (mode = "dropbox") {
        dropboxDir := ResolveDropboxFeedbackDir(baseName)
        if (dropboxDir != "") {
            DataRootProvider := "dropbox"
            return dropboxDir
        }
        DataRootProvider := "appdata"
        return A_AppData "\" baseName
    }

    if (mode = "onedrive") {
        oneDriveDir := ResolveOneDriveFeedbackDir(baseName)
        if (oneDriveDir != "") {
            DataRootProvider := "onedrive"
            return oneDriveDir
        }
        DataRootProvider := "appdata"
        return A_AppData "\" baseName
    }

    if (mode = "appdata") {
        DataRootProvider := "appdata"
        return A_AppData "\" baseName
    }

    if UseCloudPortableStorage {
        dropboxDir := ResolveDropboxFeedbackDir(baseName)
        if (dropboxDir != "") {
            DataRootProvider := "dropbox"
            return dropboxDir
        }

        oneDriveDir := ResolveOneDriveFeedbackDir(baseName)
        if (oneDriveDir != "") {
            DataRootProvider := "onedrive"
            return oneDriveDir
        }
    }

    DataRootProvider := "appdata"
    return A_AppData "\" baseName
}

; Handles resolve dropbox feedback dir.
ResolveDropboxFeedbackDir(baseName) {
    if !IsProcessRunningAny(["Dropbox", "Dropbox.exe"])
        return ""

    candidates := GetDropboxCandidateRoots()
    for _, rootPath in candidates {
        candidate := rootPath "\" baseName
        if IsDirectoryWritable(candidate)
            return candidate
    }
    return ""
}

; Handles resolve dropbox feedback dir relaxed.
ResolveDropboxFeedbackDirRelaxed(baseName) {
    candidates := GetDropboxCandidateRoots()
    for _, rootPath in candidates {
        candidate := rootPath "\" baseName
        if EnsureDirectoryExists(candidate)
            return candidate
    }
    return ""
}

; Returns or computes get dropbox candidate roots.
GetDropboxCandidateRoots() {
    roots := []
    infoPaths := []
    appData := EnvGet("APPDATA")
    localAppData := EnvGet("LOCALAPPDATA")
    programData := EnvGet("PROGRAMDATA")

    if (appData != "")
        infoPaths.Push(appData "\Dropbox\info.json")
    if (localAppData != "")
        infoPaths.Push(localAppData "\Dropbox\info.json")
    if (programData != "")
        infoPaths.Push(programData "\Dropbox\info.json")

    for _, infoPath in infoPaths {
        if !FileExist(infoPath)
            continue

        json := ReadTextFile(infoPath, "UTF-8")
        if (json = "")
            continue

        path := ExtractDropboxPath(json, "personal")
        if (path = "")
            path := ExtractDropboxPath(json, "business")
        if (path = "")
            continue

        roots.Push(path)
    }
    return roots
}

; Returns or computes extract dropbox path.
ExtractDropboxPath(json, accountType) {
    pattern := '"' accountType '"\s*:\s*\{[\s\S]*?"path"\s*:\s*"((?:\\.|[^"])*)"'
    if !RegExMatch(json, pattern, &m)
        return ""

    raw := m[1]
    raw := StrReplace(raw, "\\", "\")
    raw := StrReplace(raw, "\/", "/")
    return raw
}

; Handles resolve one drive feedback dir.
ResolveOneDriveFeedbackDir(baseName) {
    if !IsProcessRunningAny(["OneDrive", "OneDrive.exe"])
        return ""

    roots := GetOneDriveCandidateRoots()
    for _, oneDrivePath in roots {
        candidate := oneDrivePath "\" baseName
        if IsDirectoryWritable(candidate)
            return candidate
    }
    return ""
}

; Handles resolve one drive feedback dir relaxed.
ResolveOneDriveFeedbackDirRelaxed(baseName) {
    roots := GetOneDriveCandidateRoots()
    for _, oneDrivePath in roots {
        candidate := oneDrivePath "\" baseName
        if EnsureDirectoryExists(candidate)
            return candidate
    }
    return ""
}

; Returns or computes get one drive candidate roots.
GetOneDriveCandidateRoots() {
    roots := []
    root := EnvGet("OneDrive")
    if (root != "")
        roots.Push(root)
    root := EnvGet("OneDriveCommercial")
    if (root != "")
        roots.Push(root)
    root := EnvGet("OneDriveConsumer")
    if (root != "")
        roots.Push(root)
    return roots
}

; Checks whether is process running any.
IsProcessRunningAny(names) {
    for _, name in names {
        if ProcessExist(name)
            return true
    }
    return false
}

; Checks whether is directory writable.
IsDirectoryWritable(dirPath) {
    probe := ""
    try {
        if !DirExist(dirPath)
            DirCreate(dirPath)

        probe := dirPath "\.__fm_write_probe.tmp"
        FileDelete(probe)
        FileAppend("ok", probe, "UTF-8")
        FileDelete(probe)
        return true
    } catch {
        if (probe != "")
            try FileDelete(probe)
        return false
    }
}

; Creates or builds ensure directory exists.
EnsureDirectoryExists(dirPath) {
    try {
        if !DirExist(dirPath)
            DirCreate(dirPath)
        return DirExist(dirPath)
    } catch {
        return false
    }
}

; Creates or builds ensure snippet file.
EnsureSnippetFile(path) {
    EnsureParentDirectory(path)

    if FileExist(path)
        return

    tpl := "
(
{Paragraphing}:
[Main]:
Hej! Detta ar ett test med svenska tecken: å, ä, ö, Å, Ä, Ö.

Det har ar *kursiv text* och detta ar en lank: OpenAI[https://openai.com]

Vanliga halsningar,
Oscar

{Grammar}:
[Comma]:
Detta ar en separat kategori med en egen entry.
)"
    FileAppend(tpl, path, "UTF-8")
}

; Creates or builds ensure parent directory.
EnsureParentDirectory(path) {
    SplitPath path, , &dir
    if (dir != "" && !DirExist(dir))
        DirCreate(dir)
}

; Loads or deserializes load settings.
LoadSettings() {
    global SettingsFile, AppLanguage, CheckBetaReleases, ConfiguredHotkey, ShowSelectedNearClick
    global HotwheelHoldThresholdMs

    EnsureParentDirectory(SettingsFile)

    if !FileExist(SettingsFile) {
        SaveSettings()
        return
    }

    lang := IniRead(SettingsFile, "general", "language", AppLanguage)
    if (lang = "en" || lang = "sv")
        AppLanguage := lang

    betaRaw := IniRead(SettingsFile, "updates", "check_beta", "0")
    CheckBetaReleases := (betaRaw = "1")

    hk := IniRead(SettingsFile, "general", "hotkey", "")
    ConfiguredHotkey := Trim(hk)

    nearRaw := IniRead(SettingsFile, "general", "show_selected_near_click", ShowSelectedNearClick ? "1" : "0")
    ShowSelectedNearClick := (nearRaw = "1")

    holdRaw := IniRead(SettingsFile, "general", "hotwheel_hold_threshold_ms", HotwheelHoldThresholdMs "")
    HotwheelHoldThresholdMs := NormalizeHotwheelHoldThresholdMs(holdRaw)

    ScriptRunnerLoadFromSettings()
}

; Saves or serializes save settings.
SaveSettings() {
    global SettingsFile, AppLanguage, CheckBetaReleases, ConfiguredHotkey, StorageMode
    global ShowSelectedNearClick, HotwheelHoldThresholdMs

    EnsureParentDirectory(SettingsFile)
    IniWrite(AppLanguage, SettingsFile, "general", "language")
    IniWrite(ConfiguredHotkey, SettingsFile, "general", "hotkey")
    IniWrite(StorageMode, SettingsFile, "general", "storage_mode")
    IniWrite(ShowSelectedNearClick ? "1" : "0", SettingsFile, "general", "show_selected_near_click")
    IniWrite(NormalizeHotwheelHoldThresholdMs(HotwheelHoldThresholdMs), SettingsFile, "general", "hotwheel_hold_threshold_ms")
    IniWrite(CheckBetaReleases ? "1" : "0", SettingsFile, "updates", "check_beta")
    ScriptRunnerSaveToSettings()
    SaveStorageMode()
}

; Returns or computes get legacy app data settings path.
GetLegacyAppDataSettingsPath() {
    return A_AppData "\PasteMenu\settings.ini"
}

; Loads or deserializes load storage mode.
LoadStorageMode() {
    global StorageBootstrapFile, StorageMode

    EnsureParentDirectory(StorageBootstrapFile)

    mode := StrLower(Trim(IniRead(StorageBootstrapFile, "general", "storage_mode", "")))
    if (mode != "auto" && mode != "dropbox" && mode != "onedrive" && mode != "appdata") {
        legacySettings := GetLegacyAppDataSettingsPath()
        mode := StrLower(Trim(IniRead(legacySettings, "general", "storage_mode", StorageMode)))
    }

    if (mode = "auto" || mode = "dropbox" || mode = "onedrive" || mode = "appdata")
        StorageMode := mode
}

; Saves or serializes save storage mode.
SaveStorageMode() {
    global StorageBootstrapFile, StorageMode

    EnsureParentDirectory(StorageBootstrapFile)
    IniWrite(StorageMode, StorageBootstrapFile, "general", "storage_mode")
}

; Handles t.
T(key) {
    global AppLanguage
    lang := AppLanguage

    if (lang = "sv") {
        switch key {
            case "menu_empty_category": return "(tom kategori)"
            case "menu_quick_new_entry": return "Ny post (snabb)..."
            case "menu_edit_category": return "Redigera kategori"
            case "menu_selected_entry": return "Vald post"
            case "menu_last_selected_entry": return "Senast vald"
            case "menu_edit": return "Redigera..."
            case "menu_new_entry": return "Ny post..."
            case "menu_rename": return "Byt namn..."
            case "menu_move_to": return "Flytta till"
            case "menu_delete_category": return "Radera kategori..."
            case "menu_settings": return "Inställningar"
            case "menu_new_category": return "Ny kategori"
            case "menu_show_storage": return "Visa filer"
            case "menu_validate_fix_now": return "Validera/Fixa nu..."
            case "menu_language": return "Språk"
            case "menu_language_en": return "English"
            case "menu_language_sv": return "Svenska"
            case "menu_configure_hotkey": return "Konfigurera snabbtangent..."
            case "menu_open_settings": return "Öppna inställningar"
            case "menu_entry_editor": return "Entry editor"
            case "menu_run_script": return "Kör script"
            case "menu_paste_script_text": return "Klistra in script som text"
            case "menu_run_script_refresh": return "Uppdatera scripts"
            case "menu_run_script_open_folder": return "Öppna scriptmapp"
            case "menu_run_script_empty": return "(inga körbara scripts)"
            case "menu_script_paste_prefix": return "[Text]"
            case "menu_check_updates": return "Sök uppdateringar (placeholder)"
            case "menu_close": return "Stäng"
            case "menu_exit": return "Avsluta"
            case "toggle_beta_on": return "Betautgåvor: PÅ"
            case "toggle_beta_off": return "Betautgåvor: AV"
            case "msg_storage_title": return "Lagringsplats"
            case "msg_storage_path": return "Sökväg"
            case "msg_storage_provider": return "Källa"
            case "provider_dropbox": return "Dropbox"
            case "provider_onedrive": return "OneDrive"
            case "provider_appdata": return "AppData"
            case "settings_storage_type": return "Lagringstyp"
            case "storage_mode_auto": return "Automatiskt (Dropbox > OneDrive > AppData)"
            case "storage_mode_dropbox": return "Dropbox"
            case "storage_mode_onedrive": return "OneDrive"
            case "storage_mode_appdata": return "AppData"
            case "msg_settings_saved": return "Inställning sparad."
            case "msg_validate_ok": return "Validering klar: ingen strukturell fix behövs."
            case "msg_validate_skipped": return "Validering klar: fix hoppades över."
            case "msg_updates_placeholder_title": return "Uppdateringar"
            case "msg_updates_placeholder": return "Uppdateringskontroll är inte aktiverad ännu.`nNär repo/release-flöde är klart kan denna funktion anslutas."
            case "msg_hotkey_saved": return "Snabbtangent sparad."
            case "msg_hotkey_invalid": return "Kunde inte registrera snabbtangent. Återgår till ^F9."
            case "msg_hotkey_firstrun_title": return "Första inställning"
            case "msg_hotkey_firstrun_prompt": return "Välj en snabbtangent nu.`nRekommendation: använd funktionstangent eller modifierare (t.ex. ^F9, !F10, +F8)."
            case "msg_hotkey_recommend": return "Rekommendation: använd funktionstangent eller modifierare."
            case "msg_sync_title": return "Importera lokal fil"
            case "msg_sync_prompt": return "Hittade en lokal pastemenu.txt bredvid skriptet/exe.`nVill du ersätta den persistenta filen?"
            case "msg_sync_source": return "Källa"
            case "msg_sync_target": return "Mål"
            case "msg_sync_reason_newer": return "Den lokala filen är nyare."
            case "msg_sync_reason_larger": return "Den lokala filen är större."
            case "msg_sync_reason_newer_larger": return "Den lokala filen är både nyare och större."
            case "msg_sync_reason_missing": return "Ingen persistent fil hittades."
            case "msg_sync_done": return "Persistent fil ersatt med den lokala."
            case "msg_sync_failed": return "Kunde inte läsa eller skriva filen."
            case "msg_migrate_title": return "Flytta till Dropbox"
            case "msg_migrate_prompt": return "En lokal pastemenu.txt hittades i AppData och Dropbox är tillgängligt.`nVill du flytta filen till Dropbox?"
            case "msg_migrate_done": return "Filen flyttades till Dropbox och lagringstypen sattes till Dropbox."
            case "msg_migrate_failed": return "Flytten till Dropbox misslyckades."
            case "msg_text_context_required": return "Fokusera ett textfält först (markör eller markerad text)."
            case "msg_text_or_folder_context_required": return "Fokusera ett textfält eller välj en mapp i Utforskaren först."
            case "msg_paste_target_lost": return "Kunde inte återställa textfältet för inklistring."
            case "hotkey_dialog_title": return "Konfigurera snabbtangent"
            case "hotkey_dialog_current": return "Vald snabbtangent"
            case "hotkey_dialog_listening": return "Lyssnar... tryck tangent eller musknapp (Esc avbryter)"
            case "hotkey_dialog_click": return "Klicka på snabbtangentsraden och tryck tangentkombination eller musknapp."
            case "hotkey_dialog_capture_cancelled": return "Avlyssning avbruten."
            case "hotkey_dialog_save": return "Spara"
            case "hotkey_dialog_cancel": return "Avbryt"
            case "settings_window_title": return "Inställningar - PasteMenu"
            case "settings_tab_texts": return "Texter"
            case "settings_tab_scripts": return "Scripts"
            case "settings_storage": return "Lagring"
            case "settings_hotkey": return "Snabbtangent"
            case "settings_hotwheel_hold_ms": return "Hålltröskel (ms)"
            case "editor_move": return "Flytta"
            case "msg_move_no_target_category": return "Ingen annan kategori finns att flytta till."
            case "msg_move_target_prompt": return "Flytta posten till kategori:"
            case "editor_show_selected_near_click": return "Visa post nära klick i huvudmenyn"
            case "settings_language": return "Språk"
            case "settings_beta": return "Betautgåvor"
            case "settings_scripts": return "Script runner"
            case "settings_scripts_enable": return "Aktivera scriptfunktionalitet"
            case "settings_scripts_folder": return "Scriptmapp"
            case "settings_scripts_browse": return "Bläddra..."
            case "settings_scripts_refresh": return "Uppdatera"
            case "settings_scripts_configure": return "Konfigurera scripts..."
            case "settings_scripts_recursive": return "Inkludera undermappar"
            case "settings_scripts_require_confirm": return "Bekräfta innan körning"
            case "settings_scripts_show_console": return "Visa konsolfönster"
            case "settings_scripts_wait_for_exit": return "Vänta på att script slutar"
            case "settings_scripts_max_items": return "Max antal"
            case "settings_validate": return "Validera/Fixa nu"
            case "settings_restore": return "Återställ backup"
            case "settings_undo": return "Ångra"
            case "settings_updates": return "Sök uppdateringar (placeholder)"
            case "settings_new_category": return "Ny kategori"
            case "settings_migrate": return "Migrera"
            case "settings_close": return "Stäng"
            case "restore_window_title": return "Återställ backup"
            case "restore_action": return "Återställ"
            case "msg_no_backups": return "Inga backuper hittades."
            case "msg_restore_done": return "Backup återställd."
            case "msg_restore_failed": return "Kunde inte återställa backup."
            case "msg_restore_confirm": return "Ersätt aktuell pastemenu.txt med vald backup?"
            case "msg_undo_done": return "Återställning ångrad."
            case "msg_undo_failed": return "Kunde inte ångra senaste återställningen."
            case "msg_undo_none": return "Inget att ångra."
            case "msg_script_runner_disabled": return "Script runner är avstängd."
            case "msg_script_folder_missing": return "Scriptmapp saknas eller kan inte nås."
            case "msg_script_run_confirm": return "Köra script?`n`n{1}"
            case "msg_script_run_failed": return "Kunde inte köra scriptet."
            case "msg_script_no_mapping": return "Ingen interpreter-mappning för filtypen."
            case "msg_script_outside_folder": return "Scriptet ligger utanför vald scriptmapp."
            case "script_mapping_title": return "Scriptmappningar"
            case "script_mapping_ext": return "Ext"
            case "script_mapping_runner": return "Runner"
            case "script_mapping_args": return "Argument"
            case "script_mapping_add_update": return "Lägg till/uppdatera"
            case "script_mapping_delete": return "Ta bort"
            case "script_mapping_save": return "Spara"
            case "script_mapping_cancel": return "Avbryt"
            case "script_mapping_hint": return "Tips: använd {script} för scriptfil och {folder} för vald mapp."
            case "msg_script_mapping_invalid": return "Ange filändelse och runner."
            case "msg_script_mapping_saved": return "Scriptmappningar sparade."
            case "backup_tier_change": return "per ändring"
            case "backup_tier_minute": return "per minut"
            case "backup_tier_tenmin": return "per tio minuter"
            case "backup_tier_hour": return "timvis"
            case "backup_tier_day": return "daglig"
            case "backup_tier_week": return "veckovis"
            case "backup_tier_month": return "månadsvis"
            case "change_add": return "Ny"
            case "change_edit": return "Redigera"
            case "change_delete": return "Radera"
            case "change_unknown": return "Ändring"
            case "time_just_now": return "just nu"
            case "time_second_one": return "en sekund sedan"
            case "time_second_many": return "{1} sekunder sedan"
            case "time_minute_one": return "en minut sedan"
            case "time_minute_many": return "{1} minuter sedan"
            case "time_hour_one": return "en timme sedan"
            case "time_hour_many": return "{1} timmar sedan"
            case "time_day_one": return "en dag sedan"
            case "time_day_many": return "{1} dagar sedan"
            case "time_week_one": return "en vecka sedan"
            case "time_week_many": return "{1} veckor sedan"
            case "time_month_one": return "en månad sedan"
            case "time_month_many": return "{1} månader sedan"
            case "time_year_one": return "ett år sedan"
            case "time_year_many": return "{1} år sedan"
            case "tray_open_editor": return "Öppna editor"
            case "tray_open_settings": return "Öppna inställningar"
            case "msg_fix_title": return "PasteMenu v3"
            case "msg_fix_prompt": return "Formateringsproblem hittades i snippet-filen.`n`nVill du försöka en automatisk fix nu?`n(En backup skapas.)"
            case "updates_mode_label": return "Läge"
            case "updates_mode_stable": return "Stabila utgåvor"
            case "updates_mode_beta": return "Beta + stabila utgåvor"
            default: return key
        }
    }

    ; English default
    switch key {
        case "menu_empty_category": return "(empty category)"
        case "menu_quick_new_entry": return "New entry (quick)..."
        case "menu_edit_category": return "Edit Category"
        case "menu_selected_entry": return "Selected entry"
        case "menu_last_selected_entry": return "Last selected"
        case "menu_edit": return "Edit..."
        case "menu_new_entry": return "New entry..."
        case "menu_rename": return "Rename..."
        case "menu_move_to": return "Move to"
        case "menu_delete_category": return "Delete category..."
        case "menu_settings": return "Settings"
        case "menu_new_category": return "New category"
        case "menu_show_storage": return "Show files"
        case "menu_validate_fix_now": return "Validate/Fix now..."
        case "menu_language": return "Language"
        case "menu_language_en": return "English"
        case "menu_language_sv": return "Svenska"
        case "menu_configure_hotkey": return "Configure hotkey..."
        case "menu_open_settings": return "Open settings"
        case "menu_entry_editor": return "Entry editor"
        case "menu_run_script": return "Run script"
        case "menu_paste_script_text": return "Paste script as text"
        case "menu_run_script_refresh": return "Refresh scripts"
        case "menu_run_script_open_folder": return "Open scripts folder"
        case "menu_run_script_empty": return "(no runnable scripts)"
        case "menu_script_paste_prefix": return "[Text]"
        case "menu_check_updates": return "Check for updates (placeholder)"
        case "menu_close": return "Close"
        case "menu_exit": return "Exit"
        case "toggle_beta_on": return "Check beta releases: ON"
        case "toggle_beta_off": return "Check beta releases: OFF"
        case "msg_storage_title": return "Storage Location"
        case "msg_storage_path": return "Path"
        case "msg_storage_provider": return "Provider"
        case "provider_dropbox": return "Dropbox"
        case "provider_onedrive": return "OneDrive"
        case "provider_appdata": return "AppData"
        case "settings_storage_type": return "Storage type"
        case "storage_mode_auto": return "Automatic (Dropbox > OneDrive > AppData)"
        case "storage_mode_dropbox": return "Dropbox"
        case "storage_mode_onedrive": return "OneDrive"
        case "storage_mode_appdata": return "AppData"
        case "msg_settings_saved": return "Setting saved."
        case "msg_validate_ok": return "Validation complete: no structural fix needed."
        case "msg_validate_skipped": return "Validation complete: fix was skipped."
        case "msg_updates_placeholder_title": return "Updates"
        case "msg_updates_placeholder": return "Update checking is not active yet.`nWhen repo/release flow is ready, this action can be wired."
        case "msg_hotkey_saved": return "Hotkey saved."
        case "msg_hotkey_invalid": return "Could not register hotkey. Falling back to ^F9."
        case "msg_hotkey_firstrun_title": return "First-time setup"
        case "msg_hotkey_firstrun_prompt": return "Please choose a hotkey now.`nRecommendation: use a function key or modifiers (e.g. ^F9, !F10, +F8)."
        case "msg_hotkey_recommend": return "Recommendation: use a function key or modifiers."
        case "msg_sync_title": return "Import local file"
        case "msg_sync_prompt": return "Found a local pastemenu.txt next to the script/exe.`nReplace the persistent file with it?"
        case "msg_sync_source": return "Source"
        case "msg_sync_target": return "Target"
        case "msg_sync_reason_newer": return "The local file is newer."
        case "msg_sync_reason_larger": return "The local file is larger."
        case "msg_sync_reason_newer_larger": return "The local file is both newer and larger."
        case "msg_sync_reason_missing": return "No persistent file was found."
        case "msg_sync_done": return "Persistent file replaced from local file."
        case "msg_sync_failed": return "Could not read or write the file."
        case "msg_migrate_title": return "Move to Dropbox"
        case "msg_migrate_prompt": return "A local pastemenu.txt was found in AppData and Dropbox is available.`nMove it to Dropbox now?"
        case "msg_migrate_done": return "File moved to Dropbox and storage mode set to Dropbox."
        case "msg_migrate_failed": return "Move to Dropbox failed."
        case "msg_text_context_required": return "Focus a text field first (caret or selected text)."
        case "msg_text_or_folder_context_required": return "Focus a text field or select a folder in Explorer first."
        case "msg_paste_target_lost": return "Could not restore the text target for paste."
        case "hotkey_dialog_title": return "Configure Hotkey"
        case "hotkey_dialog_current": return "Selected hotkey"
        case "hotkey_dialog_listening": return "Listening... press a key combo or mouse button (Esc cancels)"
        case "hotkey_dialog_click": return "Click the hotkey line and press your key combination or a mouse button."
        case "hotkey_dialog_capture_cancelled": return "Capture cancelled."
        case "hotkey_dialog_save": return "Save"
        case "hotkey_dialog_cancel": return "Cancel"
        case "settings_window_title": return "Settings - PasteMenu"
        case "settings_tab_texts": return "Texts"
        case "settings_tab_scripts": return "Scripts"
        case "settings_storage": return "Storage"
        case "settings_hotkey": return "Hotkey"
        case "settings_hotwheel_hold_ms": return "Hold threshold (ms)"
        case "editor_move": return "Move"
        case "msg_move_no_target_category": return "No other category is available to move to."
        case "msg_move_target_prompt": return "Move entry to category:"
        case "editor_show_selected_near_click": return "Show entry near click in root menu"
        case "settings_language": return "Language"
        case "settings_beta": return "Beta releases"
        case "settings_scripts": return "Script runner"
        case "settings_scripts_enable": return "Enable script functionality"
        case "settings_scripts_folder": return "Scripts folder"
        case "settings_scripts_browse": return "Browse..."
        case "settings_scripts_refresh": return "Refresh"
        case "settings_scripts_configure": return "Configure scripts..."
        case "settings_scripts_recursive": return "Include subfolders"
        case "settings_scripts_require_confirm": return "Confirm before running"
        case "settings_scripts_show_console": return "Show console window"
        case "settings_scripts_wait_for_exit": return "Wait for script to finish"
        case "settings_scripts_max_items": return "Max items"
        case "settings_validate": return "Validate/Fix now"
        case "settings_restore": return "Restore backup"
        case "settings_undo": return "Undo"
        case "settings_updates": return "Check updates (placeholder)"
        case "settings_new_category": return "New category"
        case "settings_migrate": return "Migrate"
        case "settings_close": return "Close"
        case "restore_window_title": return "Restore backup"
        case "restore_action": return "Restore"
        case "msg_no_backups": return "No backups were found."
        case "msg_restore_done": return "Backup restored."
        case "msg_restore_failed": return "Could not restore backup."
        case "msg_restore_confirm": return "Replace current pastemenu.txt with selected backup?"
        case "msg_undo_done": return "Restore undone."
        case "msg_undo_failed": return "Could not undo last restore."
        case "msg_undo_none": return "Nothing to undo."
        case "msg_script_runner_disabled": return "Script runner is disabled."
        case "msg_script_folder_missing": return "Scripts folder is missing or unavailable."
        case "msg_script_run_confirm": return "Run script?`n`n{1}"
        case "msg_script_run_failed": return "Could not run script."
        case "msg_script_no_mapping": return "No interpreter mapping exists for this extension."
        case "msg_script_outside_folder": return "Script path is outside the selected scripts folder."
        case "script_mapping_title": return "Script mappings"
        case "script_mapping_ext": return "Ext"
        case "script_mapping_runner": return "Runner"
        case "script_mapping_args": return "Arguments"
        case "script_mapping_add_update": return "Add/Update"
        case "script_mapping_delete": return "Delete"
        case "script_mapping_save": return "Save"
        case "script_mapping_cancel": return "Cancel"
        case "script_mapping_hint": return "Tip: use {script} for script file and {folder} for selected folder."
        case "msg_script_mapping_invalid": return "Provide both extension and runner."
        case "msg_script_mapping_saved": return "Script mappings saved."
        case "backup_tier_change": return "per change"
        case "backup_tier_minute": return "per minute"
        case "backup_tier_tenmin": return "per ten minutes"
        case "backup_tier_hour": return "hourly"
        case "backup_tier_day": return "daily"
        case "backup_tier_week": return "weekly"
        case "backup_tier_month": return "monthly"
        case "change_add": return "Add"
        case "change_edit": return "Edit"
        case "change_delete": return "Delete"
        case "change_unknown": return "Change"
        case "time_just_now": return "just now"
        case "time_second_one": return "one second ago"
        case "time_second_many": return "{1} seconds ago"
        case "time_minute_one": return "one minute ago"
        case "time_minute_many": return "{1} minutes ago"
        case "time_hour_one": return "one hour ago"
        case "time_hour_many": return "{1} hours ago"
        case "time_day_one": return "one day ago"
        case "time_day_many": return "{1} days ago"
        case "time_week_one": return "one week ago"
        case "time_week_many": return "{1} weeks ago"
        case "time_month_one": return "one month ago"
        case "time_month_many": return "{1} months ago"
        case "time_year_one": return "one year ago"
        case "time_year_many": return "{1} years ago"
        case "tray_open_editor": return "Open editor"
        case "tray_open_settings": return "Open settings"
        case "msg_fix_title": return "PasteMenu v3"
        case "msg_fix_prompt": return "Formatting issues were detected in the snippet file.`n`nApply automatic fix now?`n(A backup will be created.)"
        case "updates_mode_label": return "Mode"
        case "updates_mode_stable": return "Stable releases"
        case "updates_mode_beta": return "Beta + stable releases"
        default: return key
    }
}

; Returns or computes get provider display name.
GetProviderDisplayName() {
    global DataRootProvider
    if (DataRootProvider = "dropbox")
        return T("provider_dropbox")
    if (DataRootProvider = "onedrive")
        return T("provider_onedrive")
    return T("provider_appdata")
}

; Returns or computes get storage mode choices.
GetStorageModeChoices() {
    return [
        T("storage_mode_auto"),
        T("storage_mode_dropbox"),
        T("storage_mode_onedrive"),
        T("storage_mode_appdata")
    ]
}

; Handles storage mode to choice index.
StorageModeToChoiceIndex(mode) {
    m := StrLower(Trim(mode))
    if (m = "dropbox")
        return 2
    if (m = "onedrive")
        return 3
    if (m = "appdata")
        return 4
    return 1
}

; Handles storage mode from choice.
StorageModeFromChoice(choiceText) {
    if (choiceText = T("storage_mode_dropbox"))
        return "dropbox"
    if (choiceText = T("storage_mode_onedrive"))
        return "onedrive"
    if (choiceText = T("storage_mode_appdata"))
        return "appdata"
    return "auto"
}

; Handles storage mode from choice index.
StorageModeFromChoiceIndex(idx) {
    if (idx = 2)
        return "dropbox"
    if (idx = 3)
        return "onedrive"
    if (idx = 4)
        return "appdata"
    return "auto"
}

; Sets or applies apply storage selection.
ApplyStorageSelection() {
    global StorageMode, DataRootDir, SnippetFile, SettingsFile, UsageStatsFile
    DataRootDir := ResolveDataRootDir(StorageMode)
    SnippetFile := DataRootDir "\pastemenu.txt"
    SettingsFile := DataRootDir "\settings.ini"
    UsageStatsFile := DataRootDir "\usage.ini"
}

; Handles resolve storage root strict.
ResolveStorageRootStrict(mode) {
    baseName := "PasteMenu"
    m := StrLower(Trim(mode))

    if (m = "dropbox") {
        path := ResolveDropboxFeedbackDir(baseName)
        if (path = "")
            path := ResolveDropboxFeedbackDirRelaxed(baseName)
        return path
    }
    if (m = "onedrive") {
        path := ResolveOneDriveFeedbackDir(baseName)
        if (path = "")
            path := ResolveOneDriveFeedbackDirRelaxed(baseName)
        return path
    }
    if (m = "appdata")
        return A_AppData "\" baseName
    return ResolveDataRootDir("auto")
}

; Returns or computes get app data snippet path.
GetAppDataSnippetPath() {
    return A_AppData "\PasteMenu\pastemenu.txt"
}

; Checks whether should offer app data to dropbox migration.
ShouldOfferAppDataToDropboxMigration(appDataSnippetPath, dropboxSnippetPath) {
    if !FileExist(appDataSnippetPath)
        return false
    if !FileExist(dropboxSnippetPath)
        return true

    appTime := SafeFileGetTime(appDataSnippetPath)
    dstTime := SafeFileGetTime(dropboxSnippetPath)
    appSize := SafeFileGetSize(appDataSnippetPath)
    dstSize := SafeFileGetSize(dropboxSnippetPath)

    isNewer := (appTime != "" && dstTime != "" && appTime > dstTime)
    isLarger := (appSize >= 0 && dstSize >= 0 && appSize > dstSize)
    return (isNewer || isLarger)
}

; Moves or copies copy snippet with fallback.
CopySnippetWithFallback(sourcePath, targetPath, encoding) {
    EnsureParentDirectory(targetPath)

    try {
        FileCopy(sourcePath, targetPath, 1)
        if FileExist(targetPath)
            return true
    } catch {
    }

    text := ""
    try text := FileRead(sourcePath, encoding)
    catch {
        try text := FileRead(sourcePath)
        catch {
            return false
        }
    }

    return WriteTextFileAtomic(targetPath, text, encoding)
}

; Moves or copies move snippet companion files.
MoveSnippetCompanionFiles(sourceSnippet, targetSnippet) {
    SplitPath sourceSnippet, , &sourceDir
    SplitPath targetSnippet, , &targetDir
    if (sourceDir = "" || targetDir = "")
        return
    if PathsEqual(sourceDir, targetDir)
        return

    Loop Files, sourceDir "\pastemenu.txt*", "F" {
        src := A_LoopFileFullPath
        if PathsEqual(src, sourceSnippet)
            continue
        dst := targetDir "\" A_LoopFileName
        try {
            FileCopy(src, dst, 1)
            if FileExist(dst)
                try FileDelete(src)
        }
    }

    sourceBackupDir := sourceDir "\backups"
    targetBackupDir := targetDir "\backups"
    if DirExist(sourceBackupDir) {
        try {
            DirCopy(sourceBackupDir, targetBackupDir, 1)
            if DirExist(targetBackupDir)
                try DirDelete(sourceBackupDir, 1)
        }
    }
}

; Moves or copies copy settings with fallback.
CopySettingsWithFallback(sourcePath, targetPath) {
    EnsureParentDirectory(targetPath)

    try {
        FileCopy(sourcePath, targetPath, 1)
        if FileExist(targetPath)
            return true
    } catch {
    }

    text := ""
    try text := FileRead(sourcePath, "UTF-8")
    catch {
        try text := FileRead(sourcePath)
        catch {
            return false
        }
    }

    return WriteTextFileAtomic(targetPath, text, "UTF-8")
}

; Handles select source snippet for migration.
SelectSourceSnippetForMigration(preferredSourceSnippet, targetSnippet) {
    appDataSnippet := GetAppDataSnippetPath()

    if (preferredSourceSnippet != "" && !PathsEqual(preferredSourceSnippet, targetSnippet) && FileExist(preferredSourceSnippet))
        return preferredSourceSnippet
    if !PathsEqual(appDataSnippet, targetSnippet) && FileExist(appDataSnippet)
        return appDataSnippet
    return ""
}

; Handles select source settings for migration.
SelectSourceSettingsForMigration(preferredSourceSettings, targetSettings) {
    legacySettings := GetLegacyAppDataSettingsPath()

    if (preferredSourceSettings != "" && !PathsEqual(preferredSourceSettings, targetSettings) && FileExist(preferredSourceSettings))
        return preferredSourceSettings
    if !PathsEqual(legacySettings, targetSettings) && FileExist(legacySettings)
        return legacySettings
    return ""
}

; Handles maybe offer app data to dropbox migration.
MaybeOfferAppDataToDropboxMigration() {
    global SnippetEncoding, StorageMode, SettingsFile

    appDataSnippet := GetAppDataSnippetPath()
    if !FileExist(appDataSnippet)
        return false

    dropboxDir := ResolveDropboxFeedbackDir("PasteMenu")
    if (dropboxDir = "")
        return false

    dropboxSnippet := dropboxDir "\pastemenu.txt"
    dropboxSettings := dropboxDir "\settings.ini"
    if PathsEqual(appDataSnippet, dropboxSnippet)
        return false
    if !ShouldOfferAppDataToDropboxMigration(appDataSnippet, dropboxSnippet)
        return false

    prompt := T("msg_migrate_prompt")
    prompt .= "`n`n" T("msg_sync_source") ":`n" appDataSnippet
    prompt .= "`n`n" T("msg_sync_target") ":`n" dropboxSnippet
    ans := MsgBox(prompt, T("msg_migrate_title"), "YesNo Icon?")
    if (ans != "Yes")
        return false

    if !CopySnippetWithFallback(appDataSnippet, dropboxSnippet, SnippetEncoding) {
        MsgBox T("msg_migrate_failed"), T("msg_migrate_title")
        return false
    }
    if !FileExist(dropboxSnippet) {
        MsgBox T("msg_migrate_failed"), T("msg_migrate_title")
        return false
    }

    sourceSettings := SelectSourceSettingsForMigration(SettingsFile, dropboxSettings)
    if (sourceSettings != "") {
        if !CopySettingsWithFallback(sourceSettings, dropboxSettings) {
            MsgBox T("msg_migrate_failed"), T("msg_migrate_title")
            return false
        }
        if !FileExist(dropboxSettings) {
            MsgBox T("msg_migrate_failed"), T("msg_migrate_title")
            return false
        }
        try FileDelete(sourceSettings)
    }

    ; Best effort cleanup of old AppData copy after successful write.
    MoveSnippetCompanionFiles(appDataSnippet, dropboxSnippet)
    try FileDelete(appDataSnippet)

    StorageMode := "dropbox"
    ApplyStorageSelection()
    SaveSettings()
    MsgBox T("msg_migrate_done"), T("msg_migrate_title")
    return true
}

; Initializes or controls register configured hotkey.
