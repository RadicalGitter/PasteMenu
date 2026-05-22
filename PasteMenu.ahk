#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =====================================================================
;  SNABBGUIDE - EXTERN FIL (pastemenu.txt)
; ---------------------------------------------------------------------
;  Struktur:
;    {Kategori}:
;    [Rubrik]:
;    Text...
;
;    [Rubrik2]: Kort text pa samma rad
;
;  Exempel:
;    {Paragraphing}:
;    [Main]:
;    Detta ar *kursiv text* och en lank OpenAI[https://openai.com]
;
;  Hotkey:
;    Konfigureras i Settings (standard: ^F9).
; =====================================================================

; =========================== SEKTION 1 (ANDRA HAR) ===========================
UseCloudPortableStorage := true ; Dropbox (first) -> OneDrive (second) -> AppData fallback.
DataRootProvider := "appdata"
DataRootDir      := A_AppData "\PasteMenu"
SnippetFile      := DataRootDir "\pastemenu.txt"
SettingsFile     := DataRootDir "\settings.ini"
StorageBootstrapFile := A_AppData "\PasteMenu\storage.ini"
SnippetEncoding  := "UTF-8"   ; Andra till "CP1252" om filen inte ar UTF-8.
EnableRichText   := true      ; Forsok klistra in italics + lankar som rich text (HTML).
EnableLinkMarkup := true      ; Konvertera linktext[link] till klickbar lank.
DefaultCategory  := "General"
AppLanguage      := "en"
CheckBetaReleases := false
ConfiguredHotkey := "" ; e.g. ^F9
StorageMode      := "auto" ; auto | dropbox | onedrive | appdata
ShowSelectedNearClick := false

; ======================= SLUT PA SEKTION 1 (ANDRA HAR) =======================


; ---------------------------- TEKNISK DEL ----------------------------
_Categories           := []
_EntriesByCategory    := Map() ; category -> Map(title -> content)
_EntryOrderByCategory := Map() ; category -> Array(title)
_EditorState          := 0
_DragState            := 0
_DragGhost            := 0
_DragHighResTimer     := false
_CurrentHotkeyRegistered := ""
_SettingsWindowState  := 0
_UndoState            := 0
_MenuAutoCloseState   := 0
_PointerContext       := {lastIBeamTick: 0, lastIBeamRoot: 0}
_TextContextState     := {lastTick: 0, lastRoot: 0}
_SelectedMenuCategory := ""
_SelectedMenuTitle    := ""
_LastSelectedMenuCategory := ""
_LastSelectedMenuTitle    := ""
_PendingPasteTarget   := 0

; Drag/drop handlers for editor list controls.
OnMessage(0x0201, Editor_OnLButtonDown) ; WM_LBUTTONDOWN
OnMessage(0x0202, Editor_OnLButtonUp)   ; WM_LBUTTONUP
OnMessage(0x007B, Editor_OnContextMenu) ; WM_CONTEXTMENU
OnMessage(0x0100, Editor_OnKeyDown)     ; WM_KEYDOWN
SetTimer(UpdatePointerContext, 100)

InitOnStartup()

; Handles resolve data root dir.
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
}

; Saves or serializes save settings.
SaveSettings() {
    global SettingsFile, AppLanguage, CheckBetaReleases, ConfiguredHotkey, StorageMode
    global ShowSelectedNearClick

    EnsureParentDirectory(SettingsFile)
    IniWrite(AppLanguage, SettingsFile, "general", "language")
    IniWrite(ConfiguredHotkey, SettingsFile, "general", "hotkey")
    IniWrite(StorageMode, SettingsFile, "general", "storage_mode")
    IniWrite(ShowSelectedNearClick ? "1" : "0", SettingsFile, "general", "show_selected_near_click")
    IniWrite(CheckBetaReleases ? "1" : "0", SettingsFile, "updates", "check_beta")
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
            case "msg_paste_target_lost": return "Kunde inte återställa textfältet för inklistring."
            case "hotkey_dialog_title": return "Konfigurera snabbtangent"
            case "hotkey_dialog_current": return "Vald snabbtangent"
            case "hotkey_dialog_listening": return "Lyssnar... tryck tangent eller musknapp (Esc avbryter)"
            case "hotkey_dialog_click": return "Klicka på snabbtangentsraden och tryck tangentkombination eller musknapp."
            case "hotkey_dialog_capture_cancelled": return "Avlyssning avbruten."
            case "hotkey_dialog_save": return "Spara"
            case "hotkey_dialog_cancel": return "Avbryt"
            case "settings_window_title": return "Inställningar - PasteMenu"
            case "settings_storage": return "Lagring"
            case "settings_hotkey": return "Snabbtangent"
            case "editor_move": return "Flytta"
            case "msg_move_no_target_category": return "Ingen annan kategori finns att flytta till."
            case "msg_move_target_prompt": return "Flytta posten till kategori:"
            case "editor_show_selected_near_click": return "Visa post nära klick i huvudmenyn"
            case "settings_language": return "Språk"
            case "settings_beta": return "Betautgåvor"
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
        case "msg_paste_target_lost": return "Could not restore the text target for paste."
        case "hotkey_dialog_title": return "Configure Hotkey"
        case "hotkey_dialog_current": return "Selected hotkey"
        case "hotkey_dialog_listening": return "Listening... press a key combo or mouse button (Esc cancels)"
        case "hotkey_dialog_click": return "Click the hotkey line and press your key combination or a mouse button."
        case "hotkey_dialog_capture_cancelled": return "Capture cancelled."
        case "hotkey_dialog_save": return "Save"
        case "hotkey_dialog_cancel": return "Cancel"
        case "settings_window_title": return "Settings - PasteMenu"
        case "settings_storage": return "Storage"
        case "settings_hotkey": return "Hotkey"
        case "editor_move": return "Move"
        case "msg_move_no_target_category": return "No other category is available to move to."
        case "msg_move_target_prompt": return "Move entry to category:"
        case "editor_show_selected_near_click": return "Show entry near click in root menu"
        case "settings_language": return "Language"
        case "settings_beta": return "Beta releases"
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
    global StorageMode, DataRootDir, SnippetFile, SettingsFile
    DataRootDir := ResolveDataRootDir(StorageMode)
    SnippetFile := DataRootDir "\pastemenu.txt"
    SettingsFile := DataRootDir "\settings.ini"
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
RegisterConfiguredHotkey() {
    global ConfiguredHotkey, _CurrentHotkeyRegistered

    if (ConfiguredHotkey = "")
        ConfiguredHotkey := "^F9"

    if (_CurrentHotkeyRegistered != "") {
        try Hotkey(_CurrentHotkeyRegistered, "Off")
    }

    try {
        Hotkey(ConfiguredHotkey, ShowSnippetMenu, "On")
        _CurrentHotkeyRegistered := ConfiguredHotkey
        return true
    } catch {
        ConfiguredHotkey := "^F9"
        try Hotkey("^F9", ShowSnippetMenu, "On")
        _CurrentHotkeyRegistered := "^F9"
        return false
    }
}

; Sets or applies setup tray menu.
SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("tray_open_editor"), TrayOpenEditorAction)
    A_TrayMenu.Add(T("tray_open_settings"), OpenSettingsWindow)
    A_TrayMenu.Add(T("menu_exit"), TrayExitAction)
    A_TrayMenu.Default := T("tray_open_editor")
    A_TrayMenu.ClickCount := 1
}

; Loads or deserializes load current snippet data.
LoadCurrentSnippetData(&errorMsg := "") {
    global SnippetFile, SnippetEncoding, DefaultCategory
    global _Categories, _EntriesByCategory, _EntryOrderByCategory

    EnsureSnippetFile(SnippetFile)

    categories := []
    entriesByCategory := Map()
    entryOrderByCategory := Map()
    if !LoadSnippetsFromFile(
        SnippetFile,
        SnippetEncoding,
        DefaultCategory,
        &categories,
        &entriesByCategory,
        &entryOrderByCategory
    ) {
        errorMsg := "Could not load entries from:`n" SnippetFile
        return false
    }

    _Categories := categories
    _EntriesByCategory := entriesByCategory
    _EntryOrderByCategory := entryOrderByCategory
    return true
}

; Handles tray open editor action.
TrayOpenEditorAction(*) {
    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }
    if (_Categories.Length = 0) {
        MsgBox "No categories found."
        return
    }
    OpenCategoryEditor(_Categories[1], "", false)
}

; Handles tray exit action.
TrayExitAction(*) {
    ExitApp
}

; Checks whether is modifier key name.
IsModifierKeyName(keyName) {
    static mod := Map(
        "Ctrl", 1, "LControl", 1, "RControl", 1,
        "Alt", 1, "LAlt", 1, "RAlt", 1,
        "Shift", 1, "LShift", 1, "RShift", 1,
        "LWin", 1, "RWin", 1
    )
    return mod.Has(keyName)
}

; Creates or builds build hotkey from current state.
BuildHotkeyFromCurrentState(vk, sc) {
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "" || IsModifierKeyName(keyName))
        return ""

    return BuildHotkeyWithModifiers(keyName)
}

; Creates or builds build hotkey with modifiers.
BuildHotkeyWithModifiers(keyName) {
    mods := ""
    if GetKeyState("Ctrl", "P")
        mods .= "^"
    if GetKeyState("Alt", "P")
        mods .= "!"
    if GetKeyState("Shift", "P")
        mods .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        mods .= "#"

    return mods keyName
}

; Checks whether is recommended hotkey.
IsRecommendedHotkey(hk) {
    if RegExMatch(hk, "[\^\!\+\#]")
        return true
    return RegExMatch(hk, "i)F(?:[1-9]|1\d|2[0-4])$")
}

; Handles hotkey to display.
HotkeyToDisplay(hk) {
    hk := Trim(hk)
    if (hk = "")
        return ""

    mods := []
    Loop Parse hk {
        ch := A_LoopField
        if (ch = "^")
            mods.Push("Ctrl")
        else if (ch = "!")
            mods.Push("Alt")
        else if (ch = "+")
            mods.Push("Shift")
        else if (ch = "#")
            mods.Push("Win")
        else
            break
    }

    idx := mods.Length + 1
    key := SubStr(hk, idx)
    if (key = "")
        return ""

    ; Friendly names for common non-character keys.
    if (key = "LButton")
        key := "MouseLeft"
    else if (key = "RButton")
        key := "MouseRight"
    else if (key = "MButton")
        key := "MouseMiddle"
    else if (key = "XButton1")
        key := "Mouse4"
    else if (key = "XButton2")
        key := "Mouse5"
    else if (key = "WheelUp")
        key := "WheelUp"
    else if (key = "WheelDown")
        key := "WheelDown"

    out := ""
    for i, m in mods {
        if (i > 1)
            out .= "+"
        out .= m
    }
    if (out != "")
        out .= "+"
    out .= key
    return out
}

; Handles hotkey stop capture.
HotkeyStopCapture(state) {
    state.isCapturing := false
    if IsObject(state.captureHook) {
        try state.captureHook.Stop()
        state.captureHook := 0
    }
    if IsObject(state.mouseHotkeys) {
        for hotkeyName, _ in state.mouseHotkeys {
            try Hotkey(hotkeyName, "Off")
        }
        state.mouseHotkeys := 0
    }
}

; Handles hotkey start capture.
HotkeyStartCapture(state, *) {
    HotkeyStopCapture(state)
    state.captureStartHotkey := state.selectedHotkey
    state.captureIgnoreMouseUntil := A_TickCount + 250
    state.statusText.Value := T("hotkey_dialog_listening")
    state.isCapturing := true

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := HotkeyCaptureKeyDown.Bind(state)
    state.captureHook := ih
    ih.Start()
    HotkeyRegisterCaptureMouseHotkeys(state)
}

; Handles hotkey capture cancel.
HotkeyCaptureCancel(state) {
    if (state.captureStartHotkey != "")
        state.selectedHotkey := state.captureStartHotkey
    state.hotkeyDisplay.Text := HotkeyToDisplay(state.selectedHotkey)
    HotkeyStopCapture(state)
    state.statusText.Value := T("hotkey_dialog_capture_cancelled")
    try state.btnSave.Focus()
}

; Handles hotkey register capture mouse hotkeys.
HotkeyRegisterCaptureMouseHotkeys(state) {
    hooks := Map()
    mouseKeys := ["RButton", "MButton", "XButton1", "XButton2"]
    for _, keyName in mouseKeys {
        hkName := "~*" keyName
        fn := HotkeyCaptureMouse.Bind(state, keyName)
        try {
            Hotkey(hkName, fn, "On")
            hooks[hkName] := fn
        }
    }
    state.mouseHotkeys := hooks
}

; Handles hotkey apply captured value.
HotkeyApplyCapturedValue(state, hk) {
    state.selectedHotkey := hk
    state.hotkeyDisplay.Text := HotkeyToDisplay(hk)
    HotkeyStopCapture(state)
    if IsRecommendedHotkey(hk)
        state.statusText.Value := ""
    else
        state.statusText.Value := T("msg_hotkey_recommend")
    try state.btnSave.Focus()
}

; Handles hotkey capture key down.
HotkeyCaptureKeyDown(state, ih, vk, sc) {
    if !state.isCapturing
        return

    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "Escape" || keyName = "Esc") {
        HotkeyCaptureCancel(state)
        return
    }

    hk := BuildHotkeyFromCurrentState(vk, sc)
    if (hk = "")
        return

    HotkeyApplyCapturedValue(state, hk)
}

; Handles hotkey capture mouse.
HotkeyCaptureMouse(state, keyName, *) {
    if !state.isCapturing
        return
    if (A_TickCount < state.captureIgnoreMouseUntil)
        return

    hk := BuildHotkeyWithModifiers(keyName)
    if (hk = "")
        return

    HotkeyApplyCapturedValue(state, hk)
}

; Handles hotkey dialog save.
HotkeyDialogSave(state, *) {
    global ConfiguredHotkey

    HotkeyStopCapture(state)

    chosen := state.selectedHotkey
    if (chosen = "")
        chosen := ConfiguredHotkey
    if (chosen = "")
        chosen := "^F9"

    ConfiguredHotkey := chosen
    ok := RegisterConfiguredHotkey()
    SaveSettings()

    if !ok
        MsgBox T("msg_hotkey_invalid"), T("hotkey_dialog_title")
    else if !IsRecommendedHotkey(chosen)
        MsgBox T("msg_hotkey_recommend"), T("hotkey_dialog_title")

    try state.gui.Destroy()
}

; Handles hotkey dialog cancel.
HotkeyDialogCancel(state, *) {
    global ConfiguredHotkey

    HotkeyStopCapture(state)

    if (state.forceMode && ConfiguredHotkey = "") {
        ConfiguredHotkey := "^F9"
        RegisterConfiguredHotkey()
        SaveSettings()
    }
    try state.gui.Destroy()
}

; Handles hotkey dialog escape.
HotkeyDialogEscape(state, *) {
    if (state.isCapturing) {
        HotkeyCaptureCancel(state)
        return
    }
    HotkeyDialogCancel(state)
}

; Opens or shows open hotkey config dialog.
OpenHotkeyConfigDialog(forceMode := false, *) {
    global ConfiguredHotkey

    hkGui := Gui("+AlwaysOnTop", T("hotkey_dialog_title"))
    hkGui.SetFont("s10", "Segoe UI")

    currentHotkey := ConfiguredHotkey != "" ? ConfiguredHotkey : "^F9"

    hkGui.AddText("x10 y10 w420", T("hotkey_dialog_current"))
    hotkeyDisplay := hkGui.AddText("x10 y30 w420 h28 +Border +0x100", HotkeyToDisplay(currentHotkey))
    statusText := hkGui.AddText("x10 y66 w420 h32", T("hotkey_dialog_click"))

    btnSave := hkGui.AddButton("x280 y108 w70 h30", T("hotkey_dialog_save"))
    btnCancel := hkGui.AddButton("x360 y108 w70 h30", T("hotkey_dialog_cancel"))

    state := {
        gui: hkGui,
        hotkeyDisplay: hotkeyDisplay,
        statusText: statusText,
        selectedHotkey: currentHotkey,
        forceMode: forceMode,
        isCapturing: false,
        captureHook: 0,
        mouseHotkeys: 0,
        captureStartHotkey: currentHotkey,
        captureIgnoreMouseUntil: 0,
        btnSave: btnSave
    }

    hotkeyDisplay.OnEvent("Click", HotkeyStartCapture.Bind(state))
    hotkeyDisplay.OnEvent("DoubleClick", HotkeyStartCapture.Bind(state))
    btnSave.OnEvent("Click", HotkeyDialogSave.Bind(state))
    btnCancel.OnEvent("Click", HotkeyDialogCancel.Bind(state))
    hkGui.OnEvent("Close", HotkeyDialogCancel.Bind(state))
    hkGui.OnEvent("Escape", HotkeyDialogEscape.Bind(state))

    hkGui.Show("w440 h148")
    if forceMode
        WinWaitClose("ahk_id " hkGui.Hwnd)
}

; Sets or applies settings configure hotkey action.
SettingsConfigureHotkeyAction(*) {
    OpenHotkeyConfigDialog(false)
}

; Opens or shows open settings window.
OpenSettingsWindow(*) {
    global _SettingsWindowState, AppLanguage, CheckBetaReleases, ConfiguredHotkey
    global StorageMode, DataRootDir

    if IsObject(_SettingsWindowState) {
        try {
            _SettingsWindowState.gui.Show()
            _SettingsWindowState.gui.Focus()
            return
        }
    }

    sGui := Gui("+Resize +MinSize560x370", T("settings_window_title"))
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

    btnStorage := sGui.AddButton("x10 y336 w90 h30", T("menu_show_storage"))
    btnValidate := sGui.AddButton("x108 y336 w90 h30", T("settings_validate"))
    btnRestore := sGui.AddButton("x206 y336 w90 h30", T("settings_restore"))
    btnUndo := sGui.AddButton("x304 y336 w80 h30", T("settings_undo"))
    btnUpdates := sGui.AddButton("x392 y336 w90 h30", T("settings_updates"))
    btnClose := sGui.AddButton("x490 y336 w60 h30", T("settings_close"))
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
        btnRestore: btnRestore,
        btnUndo: btnUndo
    }
    _SettingsWindowState := state

    btnHotkey.OnEvent("Click", SettingsOpenHotkeyDialog.Bind(state))
    storageDDL.OnEvent("Change", SettingsWindowStorageSelectionChanged.Bind(state))
    btnMigrate.OnEvent("Click", SettingsWindowMigrateStorage.Bind(state))
    langDDL.OnEvent("Change", SettingsWindowLanguageChanged.Bind(state))
    chkBeta.OnEvent("Click", SettingsWindowBetaChanged.Bind(state))
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
    sGui.Show("w560 h374")
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
InitOnStartup() {
    global SnippetFile, SnippetEncoding, DefaultCategory, SettingsFile, ConfiguredHotkey, StorageMode

    LoadStorageMode()
    ApplyStorageSelection()
    firstRun := !FileExist(SettingsFile)
    LoadSettings()

    MaybeOfferAppDataToDropboxMigration()

    ; Migration flow may update StorageMode/SnippetFile.
    ApplyStorageSelection()

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
ValidateAndFixSnippetFile(path, encoding, defaultCategory, promptIfDifferent := true) {
    raw := ReadTextFile(path, encoding)
    if (raw = "") {
        EnsureSnippetFile(path)
        return "Snippet file was missing or unreadable and has been recreated."
    }

    categories := []
    entriesByCategory := Map()
    entryOrderByCategory := Map()

    parsed := LoadSnippetsFromFile(path, encoding, defaultCategory, &categories, &entriesByCategory, &entryOrderByCategory)
    if !parsed {
        ; Hard recovery path: preserve original content in a single recovered entry.
        categories := [defaultCategory]
        entriesByCategory := Map()
        entryOrderByCategory := Map()
        entriesByCategory[defaultCategory] := Map()
        entryOrderByCategory[defaultCategory] := ["Recovered"]
        entriesByCategory[defaultCategory]["Recovered"] := raw
    }

    fixedText := BuildSnippetsText(categories, entriesByCategory, entryOrderByCategory)
    same := (NormalizeForCompare(raw) = NormalizeForCompare(fixedText))
    if same
        return T("msg_validate_ok")

    if promptIfDifferent {
        ans := MsgBox(
            T("msg_fix_prompt"),
            T("msg_fix_title"),
            "YesNo Icon?"
        )
        if (ans != "Yes")
            return T("msg_validate_skipped")
    }

    backupPath := path ".bak_" A_Now
    if !WriteTextFileAtomic(backupPath, raw, encoding)
        return "Validation found issues, but failed to create backup: " backupPath

    if !WriteTextFileAtomic(path, fixedText, encoding)
        return "Validation found issues, but failed to write fixed snippet file."

    return "Automatic fix complete.`nBackup created:`n" backupPath
}

; Creates or builds build snippets text.
BuildSnippetsText(categories, entriesByCategory, entryOrderByCategory) {
    out := ""
    for _, category in categories {
        if !entriesByCategory.Has(category)
            continue

        out .= "{" category "}:" "`r`n"
        order := entryOrderByCategory[category]
        for _, title in order {
            if !entriesByCategory[category].Has(title)
                continue

            content := entriesByCategory[category][title]
            out .= "[" title "]:" "`r`n"
            if (content != "")
                out .= content "`r`n"
            out .= "`r`n"
        }
        if (order.Length = 0)
            out .= "`r`n"
    }
    return out
}

; Handles normalize for compare.
NormalizeForCompare(text) {
    normalizedText := StrReplace(text, "`r`n", "`n")
    normalizedText := StrReplace(normalizedText, "`r", "`n")
    ; Ignore trailing whitespace at end of lines for comparison purposes.
    normalizedText := RegExReplace(normalizedText, "[ \t]+(?=`n)")
    ; Ignore trailing newlines.
    normalizedText := RegExReplace(normalizedText, "(?:`n)+\z")
    return normalizedText
}

; Saves or serializes write text file atomic.
WriteTextFileAtomic(path, text, encoding) {
    EnsureParentDirectory(path)

    tmp := path ".tmp"
    try FileDelete(tmp)
    try {
        FileAppend(text, tmp, encoding)
        FileMove(tmp, path, 1)
        return true
    } catch {
        try FileDelete(tmp)
        return false
    }
}

; Loads or deserializes load snippets from file.
LoadSnippetsFromFile(path, encoding, defaultCategory, &categories, &entriesByCategory, &entryOrderByCategory) {
    text := ReadTextFile(path, encoding)
    if (text = "")
        return false

    categories           := []
    entriesByCategory    := Map()
    entryOrderByCategory := Map()

    currentCategory := ""
    currentTitle    := ""
    textBuffer      := []
    lines := StrSplit(text, "`n")
    for _, raw in lines {
        line := RTrim(raw, "`r")

        if RegExMatch(line, "^\s*\{([^{}]+)\}\s*:\s*$", &catMatch) {
            CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
            currentTitle := ""
            textBuffer   := []

            currentCategory := Trim(catMatch[1])
            if (currentCategory = "")
                currentCategory := defaultCategory
            EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            continue
        }

        if RegExMatch(line, "^\s*\[([^\]]+)\]\s*:\s*(.*)$", &entryMatch) {
            CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
            textBuffer := []

            if (currentCategory = "") {
                currentCategory := defaultCategory
                EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            }

            baseTitle := Trim(entryMatch[1])
            if (baseTitle = "")
                baseTitle := "Untitled"

            title := MakeUniqueEntryTitle(baseTitle, entryOrderByCategory[currentCategory])
            currentTitle := title
            entryOrderByCategory[currentCategory].Push(title)

            inline := entryMatch[2]
            if (inline != "")
                textBuffer.Push(inline)
            continue
        }

        if (currentTitle != "") {
            textBuffer.Push(line)
            continue
        }

        ; Recover non-empty lines outside an entry by creating a placeholder entry.
        if (Trim(line) != "") {
            if (currentCategory = "") {
                currentCategory := defaultCategory
                EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            }

            recoveredTitle := MakeUniqueEntryTitle("Recovered", entryOrderByCategory[currentCategory])
            currentTitle := recoveredTitle
            entryOrderByCategory[currentCategory].Push(currentTitle)
            textBuffer := [line]
            continue
        }
    }

    CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
    return (categories.Length > 0)
}

; Handles commit entry.
CommitEntry(category, title, bufferArr, &entriesByCategory) {
    if (category = "" || title = "")
        return
    content := JoinLines(bufferArr)
    entriesByCategory[category][title] := content
}

; Creates or builds ensure category exists.
EnsureCategoryExists(category, &categories, &entriesByCategory, &entryOrderByCategory) {
    if entriesByCategory.Has(category)
        return
    categories.Push(category)
    entriesByCategory[category] := Map()
    entryOrderByCategory[category] := []
}

; Creates or builds make unique entry title.
MakeUniqueEntryTitle(baseTitle, orderArr) {
    if !FindIndexInArray(orderArr, baseTitle)
        return baseTitle

    n := 2
    while FindIndexInArray(orderArr, baseTitle " (" n ")")
        n += 1
    return baseTitle " (" n ")"
}

; Returns or computes find index in array.
FindIndexInArray(arr, needle) {
    for i, v in arr {
        if (v = needle)
            return i
    }
    return 0
}

; Returns or computes read text file.
ReadTextFile(path, encoding) {
    try {
        text := FileRead(path, encoding)
        if (encoding = "UTF-8" && InStr(text, "�")) {
            try return FileRead(path, "CP1252")
        }
        return text
    } catch {
        try return FileRead(path)
    }
    return ""
}

; Saves or serializes save snippets to file.
SaveSnippetsToFile(path, encoding, change := 0, includeChangeBackup := true) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory

    out := BuildSnippetsText(_Categories, _EntriesByCategory, _EntryOrderByCategory)
    if !WriteTextFileAtomic(path, out, encoding)
        return false

    if includeChangeBackup
        ClearUndoState()
    CreateTieredSnippetBackups(path, out, encoding, change, includeChangeBackup)
    return true
}

; Returns or computes get snippet backup dir.
GetSnippetBackupDir(snippetPath) {
    SplitPath snippetPath, , &dir
    if (dir = "")
        return ""
    return dir "\backups"
}

; Creates or builds create tiered snippet backups.
CreateTieredSnippetBackups(snippetPath, text, encoding, change := 0, includeChangeBackup := true) {
    global _SettingsWindowState

    backupDir := GetSnippetBackupDir(snippetPath)
    if (backupDir = "")
        return
    if !EnsureDirectoryExists(backupDir)
        return

    now := A_Now
    if (includeChangeBackup && IsObject(change))
        CreateDetailedChangeBackup(backupDir, change, now)

    minuteKey := FormatTime(now, "yyyyMMdd_HHmm")
    tenMinKey := BuildTenMinuteBackupKey(now)
    hourKey := FormatTime(now, "yyyyMMdd_HH")
    dayKey := FormatTime(now, "yyyyMMdd")
    weekKey := FormatTime(now, "YWeek")
    if (weekKey = "")
        weekKey := A_YWeek
    monthKey := FormatTime(now, "yyyyMM")

    ; Bucketed snapshots provide coarse recovery without backup spam.
    UpsertTierBackup(backupDir, "minute", minuteKey, text, encoding)
    UpsertTierBackup(backupDir, "tenmin", tenMinKey, text, encoding)
    UpsertTierBackup(backupDir, "hour", hourKey, text, encoding)
    UpsertTierBackup(backupDir, "day", dayKey, text, encoding)
    UpsertTierBackup(backupDir, "week", weekKey, text, encoding)
    UpsertTierBackup(backupDir, "month", monthKey, text, encoding)

    PruneTierBackups(backupDir)
    if IsObject(_SettingsWindowState)
        UpdateRestoreBackupButtonState(_SettingsWindowState)
}

; Creates or builds build ten minute backup key.
BuildTenMinuteBackupKey(yyyymmddhh24miss) {
    minuteNum := FormatTime(yyyymmddhh24miss, "mm") + 0
    bucketStart := Floor(minuteNum / 10) * 10
    return FormatTime(yyyymmddhh24miss, "yyyyMMdd_HH") Format("{:02}", bucketStart)
}

; Creates or builds create detailed change backup.
CreateDetailedChangeBackup(backupDir, change, yyyymmddhh24miss) {
    serialized := SerializeChangeBackup(change, yyyymmddhh24miss)
    if (serialized = "")
        return

    basePath := backupDir "\change_" FormatTime(yyyymmddhh24miss, "yyyyMMdd_HHmmss")
    backupPath := basePath ".pmc"
    n := 2
    while FileExist(backupPath) {
        backupPath := basePath "_" n ".pmc"
        n += 1
    }
    WriteTextFileAtomic(backupPath, serialized, "UTF-8")
}

; Handles upsert tier backup.
UpsertTierBackup(backupDir, tierName, bucketKey, text, encoding) {
    if (bucketKey = "")
        return

    backupPath := backupDir "\" tierName "_" bucketKey ".txt"
    if FileExist(backupPath) {
        existing := ReadTextFile(backupPath, encoding)
        if (NormalizeForCompare(existing) = NormalizeForCompare(text))
            return
    }
    WriteTextFileAtomic(backupPath, text, encoding)
}

; Deletes or removes prune tier backups.
PruneTierBackups(backupDir) {
    limits := Map(
        "change", 80,
        "minute", 1,
        "tenmin", 1,
        "hour", 1,
        "day", 1,
        "week", 1,
        "month", 1
    )
    byTier := Map()

    ; Group files by tier, then keep only the newest N per tier.
    Loop Files, backupDir "\*.*", "F" {
        fileName := A_LoopFileName
        if !RegExMatch(fileName, "i)^(change|minute|tenmin|hour|day|week|month)_.*\.(txt|pmc)$", &m)
            continue

        tier := StrLower(m[1])
        if !byTier.Has(tier)
            byTier[tier] := []
        byTier[tier].Push({path: A_LoopFileFullPath, modified: A_LoopFileTimeModified})
    }

    for tier, arr in byTier {
        if !limits.Has(tier)
            continue
        SortBackupItemsByModifiedDesc(arr)
        keep := limits[tier]
        for i, item in arr {
            if (i > keep)
                try FileDelete(item.path)
        }
    }
}

; Handles compare backup items by modified desc.
CompareBackupItemsByModifiedDesc(a, b, *) {
    if (a.modified = b.modified)
        return 0
    return (a.modified > b.modified) ? -1 : 1
}

; Sorts backup item arrays in-place using CompareBackupItemsByModifiedDesc().
SortBackupItemsByModifiedDesc(arr) {
    len := arr.Length
    if (len < 2)
        return arr

    ; Keep compatibility with AHK builds lacking Array.Sort().
    Loop (len - 1) {
        i := A_Index + 1
        current := arr[i]
        j := i - 1
        while (j >= 1 && CompareBackupItemsByModifiedDesc(current, arr[j]) < 0) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := current
    }
    return arr
}

; Returns or computes get available backups.
GetAvailableBackups() {
    global SnippetFile

    backups := []
    backupDir := GetSnippetBackupDir(SnippetFile)
    if (backupDir = "" || !DirExist(backupDir))
        return backups

    Loop Files, backupDir "\*.*", "F" {
        fileName := A_LoopFileName
        if !RegExMatch(fileName, "i)^(change|minute|tenmin|hour|day|week|month)_.*\.(txt|pmc)$", &m)
            continue

        tier := StrLower(m[1])
        modified := A_LoopFileTimeModified
        ageLabel := FormatRelativeBackupAge(modified)
        tierLabel := T("backup_tier_" tier)
        display := ageLabel " - " tierLabel
        isChange := false
        changeObj := 0

        if (tier = "change") {
            changeText := ReadTextFile(A_LoopFileFullPath, "UTF-8")
            if ParseChangeBackup(changeText, &parsed) {
                isChange := true
                changeObj := parsed
                display := ageLabel " - " FormatChangeBackupDisplay(parsed)
            }
        }

        backups.Push({
            path: A_LoopFileFullPath,
            tier: tier,
            modified: modified,
            display: display,
            isChange: isChange,
            change: changeObj
        })
    }

    SortBackupItemsByModifiedDesc(backups)
    return backups
}

; Handles prompt select backup index.
PromptSelectBackupIndex(backups) {
    labels := []
    for _, b in backups
        labels.Push(b.display)

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", T("restore_window_title"))
    dlg.SetFont("s10", "Segoe UI")
    list := dlg.AddListBox("x12 y12 w560 h220", labels)
    if (labels.Length > 0)
        list.Choose(1)

    btnRestore := dlg.AddButton("x394 y242 w84 h28", T("restore_action"))
    btnCancel := dlg.AddButton("x488 y242 w84 h28", T("hotkey_dialog_cancel"))

    selectedIdx := 0
    btnRestore.OnEvent("Click", (*) => (selectedIdx := list.Value, dlg.Destroy()))
    btnCancel.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Escape", (*) => dlg.Destroy())

    dlg.Show("w584 h278")
    WinWaitClose("ahk_id " dlg.Hwnd)
    return selectedIdx
}

; Returns or computes format relative backup age.
FormatRelativeBackupAge(yyyymmddhh24miss) {
    diffSec := 0
    try diffSec := DateDiff(A_Now, yyyymmddhh24miss, "Seconds")
    if (diffSec < 0)
        diffSec := 0

    if (diffSec < 1)
        return T("time_just_now")
    if (diffSec < 60)
        return FormatRelativeCount(diffSec, "time_second_one", "time_second_many")

    minutes := Floor(diffSec / 60)
    if (minutes < 60)
        return FormatRelativeCount(minutes, "time_minute_one", "time_minute_many")

    hours := Floor(diffSec / 3600)
    if (hours < 24)
        return FormatRelativeCount(hours, "time_hour_one", "time_hour_many")

    days := Floor(diffSec / 86400)
    if (days < 7)
        return FormatRelativeCount(days, "time_day_one", "time_day_many")
    if (days < 30)
        return FormatRelativeCount(Floor(days / 7), "time_week_one", "time_week_many")
    if (days < 365)
        return FormatRelativeCount(Floor(days / 30), "time_month_one", "time_month_many")
    return FormatRelativeCount(Floor(days / 365), "time_year_one", "time_year_many")
}

; Returns or computes format relative count.
FormatRelativeCount(count, oneKey, manyKey) {
    if (count <= 1)
        return T(oneKey)

    displayCount := (count <= 12) ? SmallNumberWord(count) : count
    return StrReplace(T(manyKey), "{1}", displayCount)
}

; Handles small number word.
SmallNumberWord(n) {
    global AppLanguage
    if (AppLanguage = "sv") {
        static wordsSv := Map(
            2, "tva",
            3, "tre",
            4, "fyra",
            5, "fem",
            6, "sex",
            7, "sju",
            8, "atta",
            9, "nio",
            10, "tio",
            11, "elva",
            12, "tolv"
        )
        if wordsSv.Has(n)
            return wordsSv[n]
        return n
    }

    static wordsEn := Map(
        2, "two",
        3, "three",
        4, "four",
        5, "five",
        6, "six",
        7, "seven",
        8, "eight",
        9, "nine",
        10, "ten",
        11, "eleven",
        12, "twelve"
    )
    if wordsEn.Has(n)
        return wordsEn[n]
    return n
}

; Saves or serializes serialize change backup.
SerializeChangeBackup(change, createdStamp) {
    if !IsObject(change)
        return ""

    out := "PM_CHANGE_V1`n"
    out .= "created=" createdStamp "`n"
    out .= "type=" StrLower(Trim(change.type)) "`n"
    out .= "before_category_b64=" Base64EncodeUtf8(change.beforeCategory) "`n"
    out .= "before_title_b64=" Base64EncodeUtf8(change.beforeTitle) "`n"
    out .= "before_exists=" (change.beforeExists ? "1" : "0") "`n"
    out .= "before_text_b64=" Base64EncodeUtf8(change.beforeText) "`n"
    out .= "after_category_b64=" Base64EncodeUtf8(change.afterCategory) "`n"
    out .= "after_title_b64=" Base64EncodeUtf8(change.afterTitle) "`n"
    out .= "after_exists=" (change.afterExists ? "1" : "0") "`n"
    out .= "after_text_b64=" Base64EncodeUtf8(change.afterText) "`n"
    return out
}

; Returns or computes parse change backup.
ParseChangeBackup(text, &change) {
    change := 0
    if (text = "")
        return false

    lines := StrSplit(StrReplace(text, "`r", ""), "`n")
    if (lines.Length < 2)
        return false
    if (Trim(lines[1]) != "PM_CHANGE_V1")
        return false

    ; Lightweight key=value format is easier to inspect and recover manually.
    meta := Map()
    for i, line in lines {
        if (i = 1 || Trim(line) = "")
            continue
        pos := InStr(line, "=")
        if (pos <= 1)
            continue
        key := Trim(SubStr(line, 1, pos - 1))
        val := SubStr(line, pos + 1)
        meta[key] := val
    }

    if !meta.Has("type")
        return false

    change := {
        type: meta["type"],
        created: meta.Has("created") ? meta["created"] : "",
        beforeCategory: Base64DecodeUtf8(meta.Has("before_category_b64") ? meta["before_category_b64"] : ""),
        beforeTitle: Base64DecodeUtf8(meta.Has("before_title_b64") ? meta["before_title_b64"] : ""),
        beforeExists: (meta.Has("before_exists") && meta["before_exists"] = "1"),
        beforeText: Base64DecodeUtf8(meta.Has("before_text_b64") ? meta["before_text_b64"] : ""),
        afterCategory: Base64DecodeUtf8(meta.Has("after_category_b64") ? meta["after_category_b64"] : ""),
        afterTitle: Base64DecodeUtf8(meta.Has("after_title_b64") ? meta["after_title_b64"] : ""),
        afterExists: (meta.Has("after_exists") && meta["after_exists"] = "1"),
        afterText: Base64DecodeUtf8(meta.Has("after_text_b64") ? meta["after_text_b64"] : "")
    }
    return true
}

; Returns or computes format change backup display.
FormatChangeBackupDisplay(change) {
    typeKey := "change_" StrLower(change.type)
    typeLabel := T(typeKey)
    if (typeLabel = typeKey)
        typeLabel := T("change_unknown")

    category := change.afterExists ? change.afterCategory : change.beforeCategory
    title := change.afterExists ? change.afterTitle : change.beforeTitle
    if (category = "")
        category := "?"
    if (title = "")
        title := "?"
    return typeLabel ": " category " / " title
}

; Creates or builds make entry change.
MakeEntryChange(type, beforeCategory, beforeTitle, beforeExists, beforeText, afterCategory, afterTitle, afterExists, afterText) {
    return {
        type: StrLower(type),
        beforeCategory: beforeCategory,
        beforeTitle: beforeTitle,
        beforeExists: !!beforeExists,
        beforeText: beforeText,
        afterCategory: afterCategory,
        afterTitle: afterTitle,
        afterExists: !!afterExists,
        afterText: afterText
    }
}

; Handles base 64 encode utf 8.
Base64EncodeUtf8(text) {
    if (text = "")
        return ""

    byteLen := StrPut(text, "UTF-8") - 1
    if (byteLen < 1)
        return ""

    inBuf := Buffer(byteLen, 0)
    StrPut(text, inBuf, "UTF-8")

    needed := 0
    DllCall(
        "Crypt32\CryptBinaryToStringW",
        "Ptr", inBuf,
        "UInt", byteLen,
        "UInt", 0x40000001, ; BASE64 + NOCRLF
        "Ptr", 0,
        "UInt*", &needed
    )
    outBuf := Buffer(needed * 2, 0)
    if !DllCall(
        "Crypt32\CryptBinaryToStringW",
        "Ptr", inBuf,
        "UInt", byteLen,
        "UInt", 0x40000001,
        "Ptr", outBuf,
        "UInt*", &needed
    )
        return ""
    return StrGet(outBuf, "UTF-16")
}

; Handles base 64 decode utf 8.
Base64DecodeUtf8(b64) {
    if (b64 = "")
        return ""

    byteLen := 0
    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", b64,
        "UInt", 0,
        "UInt", 0x1, ; BASE64
        "Ptr", 0,
        "UInt*", &byteLen,
        "Ptr", 0,
        "Ptr", 0
    )
        return ""

    outBuf := Buffer(byteLen, 0)
    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", b64,
        "UInt", 0,
        "UInt", 0x1,
        "Ptr", outBuf,
        "UInt*", &byteLen,
        "Ptr", 0,
        "Ptr", 0
    )
        return ""

    return StrGet(outBuf, byteLen, "UTF-8")
}

; Handles join lines.
JoinLines(arr) {
    out := ""
    for i, l in arr {
        if (i > 1)
            out .= "`r`n"
        out .= l
    }
    out := RegExReplace(out, "(?:\R)+\z", "")
    return out
}

; Opens or shows show transient tool tip.
ShowTransientToolTip(message, timeoutMs := 1400) {
    ToolTip message
    SetTimer(ClearTransientToolTip, -timeoutMs)
}

; Deletes or removes clear transient tool tip.
ClearTransientToolTip() {
    ToolTip
}

; Checks whether is text input context active.
IsTextInputContextActive() {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return false

    if IsCaretVisible() {
        RememberTextContext(activeHwnd)
        return true
    }

    focusedCtrl := ""
    try focusedCtrl := ControlGetFocus("ahk_id " activeHwnd)
    if (focusedCtrl != "") {
        ctrlHwnd := 0
        try ctrlHwnd := ControlGetHwnd(focusedCtrl, "ahk_id " activeHwnd)
        if ctrlHwnd {
            ctrlClass := ""
            try ctrlClass := WinGetClass("ahk_id " ctrlHwnd)

            if IsLikelyTextControlClass(ctrlClass) {
                RememberTextContext(activeHwnd)
                return true
            }
            if HasTextSelectionInControl(ctrlHwnd, ctrlClass) {
                RememberTextContext(activeHwnd)
                return true
            }
        }
    }

    ; If this window was recently confirmed as text context, allow mouse-bound hotkeys
    ; even when pointer is no longer above the text field.
    if IsRecentTextContextWindow(activeHwnd) {
        RememberTextContext(activeHwnd)
        return true
    }

    ; Fallback for custom-rendered text fields (browser/Electron/etc):
    ; if mouse is over the active window and cursor is/recently was IBeam, treat as text context.
    MouseGetPos ,, &mouseWin, &mouseCtrl, 2
    if (mouseWin && WindowsShareRootWindow(activeHwnd, mouseWin)) {
        if (A_Cursor = "IBeam") {
            RememberTextContext(activeHwnd)
            return true
        }
        if IsRecentIBeamOnWindow(activeHwnd) {
            RememberTextContext(activeHwnd)
            return true
        }

        if mouseCtrl {
            mouseClass := ""
            try mouseClass := WinGetClass("ahk_id " mouseCtrl)
            if IsLikelyTextControlClass(mouseClass) {
                RememberTextContext(activeHwnd)
                return true
            }
        }
    }

    return false
}

; Handles remember text context.
RememberTextContext(hwnd) {
    global _TextContextState
    if !hwnd
        return
    _TextContextState.lastTick := A_TickCount
    _TextContextState.lastRoot := GetRootWindow(hwnd)
}

; Checks whether is recent text context window.
IsRecentTextContextWindow(hwnd, maxAgeMs := 10000) {
    global _TextContextState
    if !IsObject(_TextContextState)
        return false
    if (_TextContextState.lastTick = 0)
        return false
    if (A_TickCount - _TextContextState.lastTick > maxAgeMs)
        return false
    return (_TextContextState.lastRoot = GetRootWindow(hwnd))
}

; Handles capture paste target context.
CapturePasteTargetContext() {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return 0

    focusedCtrl := ""
    ctrlHwnd := 0
    try focusedCtrl := ControlGetFocus("ahk_id " activeHwnd)
    if (focusedCtrl != "") {
        try ctrlHwnd := ControlGetHwnd(focusedCtrl, "ahk_id " activeHwnd)
    }

    return {
        win: activeHwnd,
        ctrlName: focusedCtrl,
        ctrlHwnd: ctrlHwnd
    }
}

; Handles focus paste target.
FocusPasteTarget(target) {
    if !IsObject(target)
        return false
    if !target.HasOwnProp("win") || !target.win
        return false
    if !WinExist("ahk_id " target.win)
        return false

    try WinActivate("ahk_id " target.win)
    try WinWaitActive("ahk_id " target.win, , 0.35)

    if target.HasOwnProp("ctrlName") && (target.ctrlName != "") {
        try ControlFocus(target.ctrlName, "ahk_id " target.win)
    }

    Sleep 30
    return true
}

; Handles send paste to target.
SendPasteToTarget(target) {
    if IsObject(target) {
        if target.HasOwnProp("ctrlName") && (target.ctrlName != "") {
            try {
                ControlSend("^v", target.ctrlName, "ahk_id " target.win)
                return
            }
        }
    }
    Send "^v"
}

; Updates update pointer context.
UpdatePointerContext() {
    global _PointerContext
    MouseGetPos ,, &mouseWin
    if !mouseWin
        return
    if (A_Cursor != "IBeam")
        return

    _PointerContext.lastIBeamTick := A_TickCount
    _PointerContext.lastIBeamRoot := GetRootWindow(mouseWin)
    RememberTextContext(mouseWin)
}

; Checks whether is recent i beam on window.
IsRecentIBeamOnWindow(hwnd, maxAgeMs := 900) {
    global _PointerContext
    if !IsObject(_PointerContext)
        return false
    if (_PointerContext.lastIBeamTick = 0)
        return false
    if (A_TickCount - _PointerContext.lastIBeamTick > maxAgeMs)
        return false
    return (_PointerContext.lastIBeamRoot = GetRootWindow(hwnd))
}

; Handles windows share root window.
WindowsShareRootWindow(hwndA, hwndB) {
    if (!hwndA || !hwndB)
        return false
    return (GetRootWindow(hwndA) = GetRootWindow(hwndB))
}

; Returns or computes get root window.
GetRootWindow(hwnd) {
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") ; GA_ROOT
    return root ? root : hwnd
}

; Checks whether is caret visible.
IsCaretVisible() {
    x := 0
    y := 0
    try return CaretGetPos(&x, &y)
    return false
}

; Checks whether is likely text control class.
IsLikelyTextControlClass(className) {
    if (className = "")
        return false
    return RegExMatch(
        className,
        "i)^(Edit|RICHEDIT\d*\w*|RichEdit\d*\w*|Scintilla\d*|WindowsForms10\.EDIT.*|Chrome_AutocompleteEditView|TEdit|TMemo)$"
    )
}

; Checks whether has text selection in control.
HasTextSelectionInControl(ctrlHwnd, className := "") {
    if !ctrlHwnd
        return false

    if (className = "") {
        try className := WinGetClass("ahk_id " ctrlHwnd)
    }

    if !RegExMatch(className, "i)^(Edit|RICHEDIT\d*\w*|RichEdit\d*\w*|WindowsForms10\.EDIT.*)$")
        return false

    try {
        sel := SendMessage(0x00B0, 0, 0, , "ahk_id " ctrlHwnd) ; EM_GETSEL
        selStart := sel & 0xFFFF
        selEnd := (sel >> 16) & 0xFFFF
        return (selEnd > selStart)
    }
    return false
}

; Initializes or controls start menu outside click watcher.
StartMenuOutsideClickWatcher() {
    global _MenuAutoCloseState
    _MenuAutoCloseState := {
        rDown: GetKeyState("RButton", "P"),
        mDown: GetKeyState("MButton", "P")
    }
    try Hotkey("~*LButton", MenuOutsideLeftClickHotkey, "On")
    SetTimer(MenuOutsideClickWatcherTick, 25)
}

; Initializes or controls stop menu outside click watcher.
StopMenuOutsideClickWatcher() {
    global _MenuAutoCloseState
    SetTimer(MenuOutsideClickWatcherTick, 0)
    try Hotkey("~*LButton", MenuOutsideLeftClickHotkey, "Off")
    _MenuAutoCloseState := 0
}

; Handles menu outside left click hotkey.
MenuOutsideLeftClickHotkey(*) {
    if !WinExist("ahk_class #32768")
        return

    MouseGetPos ,, &targetHwnd
    if (targetHwnd && IsMenuWindowOrChild(targetHwnd))
        return

    DllCall("EndMenu")
}

; Handles menu outside click watcher tick.
MenuOutsideClickWatcherTick() {
    global _MenuAutoCloseState
    if !IsObject(_MenuAutoCloseState)
        return

    if !WinExist("ahk_class #32768")
        return

    rNow := GetKeyState("RButton", "P")
    mNow := GetKeyState("MButton", "P")

    newClick := (rNow && !_MenuAutoCloseState.rDown)
        || (mNow && !_MenuAutoCloseState.mDown)

    _MenuAutoCloseState.rDown := rNow
    _MenuAutoCloseState.mDown := mNow

    if !newClick
        return

    MouseGetPos ,, &targetHwnd
    if (targetHwnd && IsMenuWindowOrChild(targetHwnd))
        return

    DllCall("EndMenu")
}

; Checks whether is menu window or child.
IsMenuWindowOrChild(hwnd) {
    current := hwnd
    while current {
        className := ""
        try className := WinGetClass("ahk_id " current)
        if (className = "#32768")
            return true
        current := DllCall("GetParent", "Ptr", current, "Ptr")
    }
    return false
}

; Sets or applies set selected menu entry.
SetSelectedMenuEntry(category, title) {
    global _SelectedMenuCategory, _SelectedMenuTitle
    _SelectedMenuCategory := category
    _SelectedMenuTitle := title
}

; Sets the most recently pasted entry.
SetLastSelectedMenuEntry(category, title) {
    global _LastSelectedMenuCategory, _LastSelectedMenuTitle
    _LastSelectedMenuCategory := category
    _LastSelectedMenuTitle := title
}

; Checks whether is entry pinned.
IsEntryPinned(category, title) {
    global ShowSelectedNearClick, _SelectedMenuCategory, _SelectedMenuTitle
    if !ShowSelectedNearClick
        return false
    if (category = "" || title = "")
        return false
    return (_SelectedMenuCategory = category && _SelectedMenuTitle = title)
}

; Returns or computes get selected entry for menu.
GetSelectedEntryForMenu(&category, &title) {
    global ShowSelectedNearClick, _SelectedMenuCategory, _SelectedMenuTitle
    global _EntriesByCategory

    if !ShowSelectedNearClick
        return false

    category := _SelectedMenuCategory
    title := _SelectedMenuTitle
    if (category = "" || title = "")
        return false
    if !_EntriesByCategory.Has(category)
        return false
    if !_EntriesByCategory[category].Has(title)
        return false
    return true
}

; Returns the most recently pasted entry for root-menu shortcuts.
GetLastSelectedEntryForMenu(&category, &title) {
    global _LastSelectedMenuCategory, _LastSelectedMenuTitle
    global _EntriesByCategory

    category := _LastSelectedMenuCategory
    title := _LastSelectedMenuTitle
    if (category = "" || title = "")
        return false
    if !_EntriesByCategory.Has(category) || !_EntriesByCategory[category].Has(title) {
        _LastSelectedMenuCategory := ""
        _LastSelectedMenuTitle := ""
        return false
    }
    return true
}

; Builds pinned + last-selected shortcuts for the root menu.
GetRootShortcutEntries() {
    entries := []

    if GetSelectedEntryForMenu(&pinnedCategory, &pinnedTitle) {
        entries.Push({
            category: pinnedCategory,
            title: pinnedTitle,
            label: T("menu_selected_entry") ": " pinnedTitle
        })
    }

    if GetLastSelectedEntryForMenu(&lastCategory, &lastTitle) {
        isDuplicate := false
        for _, item in entries {
            if (item.category = lastCategory && item.title = lastTitle) {
                isDuplicate := true
                break
            }
        }
        if !isDuplicate {
            entries.Push({
                category: lastCategory,
                title: lastTitle,
                label: T("menu_last_selected_entry") ": " lastTitle
            })
        }
    }

    return entries
}

; Adds root shortcut entries (pinned + last selected), with separator handling.
AddRootShortcutSection(mainMenu, nearTop, shortcutEntries) {
    if !IsObject(shortcutEntries) || (shortcutEntries.Length = 0)
        return false

    if nearTop {
        for _, item in shortcutEntries
            mainMenu.Add(item.label, PasteSnippet.Bind(item.category, item.title))
        mainMenu.Add()
    } else {
        mainMenu.Add()
        for _, item in shortcutEntries
            mainMenu.Add(item.label, PasteSnippet.Bind(item.category, item.title))
    }
    return true
}

; Handles add far root actions section.
AddFarRootActionsSection(mainMenu, openUpward) {
    primaryActions := [
        [T("menu_close"), RootCloseMenuAction],
        [T("menu_open_settings"), OpenSettingsWindow]
    ]
    secondaryActions := [
        [T("menu_new_category"), RootNewCategoryMenuAction],
        [T("menu_entry_editor"), RootEntryEditorMenuAction]
    ]

    if openUpward {
        AddRootActionItems(mainMenu, primaryActions)
        mainMenu.Add()
        AddRootActionItems(mainMenu, secondaryActions)
        mainMenu.Add()
    } else {
        mainMenu.Add()
        AddRootActionItems(mainMenu, secondaryActions)
        mainMenu.Add()
        AddRootActionItems(mainMenu, primaryActions)
    }
}

; Adds a list of `[label, handler]` action tuples to a menu.
AddRootActionItems(menuObj, actions) {
    for _, item in actions
        menuObj.Add(item[1], item[2])
}

; Returns or computes get work area for point.
GetWorkAreaForPoint(x, y, &left, &top, &right, &bottom) {
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        if (x >= mLeft && x < mRight && y >= mTop && y < mBottom) {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            return
        }
    }
    left := 0
    top := 0
    right := A_ScreenWidth
    bottom := A_ScreenHeight
}

; Handles estimate root menu height.
EstimateRootMenuHeight(categoryCount, shortcutCount := 0) {
    rowCount := categoryCount + 6 ; Root actions + separators.
    if (shortcutCount > 0)
        rowCount += shortcutCount + 1 ; Shortcut rows + separator.
    return (rowCount * 24) + 14
}

; Handles menu likely opens upward.
MenuLikelyOpensUpward(mouseX, mouseY, categoryCount, shortcutCount := 0) {
    GetWorkAreaForPoint(mouseX, mouseY, &waLeft, &waTop, &waRight, &waBottom)
    neededHeight := EstimateRootMenuHeight(categoryCount, shortcutCount)
    spaceBelow := waBottom - mouseY
    spaceAbove := mouseY - waTop

    if (spaceBelow >= neededHeight)
        return false
    if (spaceAbove >= neededHeight)
        return true
    return (spaceAbove > spaceBelow)
}

; Opens or shows show snippet menu.
ShowSnippetMenu(*) {
    global SnippetFile, SnippetEncoding, DefaultCategory
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global _PendingPasteTarget

    if !IsTextInputContextActive() {
        ShowTransientToolTip(T("msg_text_context_required"))
        return
    }

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }

    MouseGetPos &mx, &my
    _PendingPasteTarget := CapturePasteTargetContext()
    shortcutEntries := GetRootShortcutEntries()
    openUpward := MenuLikelyOpensUpward(mx, my, _Categories.Length, shortcutEntries.Length)

    mainMenu := Menu()
    if openUpward
        AddFarRootActionsSection(mainMenu, true)
    if !openUpward
        AddRootShortcutSection(mainMenu, true, shortcutEntries)

    for _, category in _Categories {
        sub := Menu()
        order := _EntryOrderByCategory[category]

        if (order.Length = 0) {
            sub.Add(T("menu_empty_category"), NoOp)
        } else {
            for _, title in order
                sub.Add(title, PasteSnippet.Bind(category, title))
        }

        sub.Add()
        sub.Add(T("menu_quick_new_entry"), QuickNewEntryMenuAction.Bind(category))

        editSub := Menu()
        editSub.Add(T("menu_new_entry"), NewEntryMenuAction.Bind(category))
        editSub.Add(T("menu_rename"), RenameCategoryMenuAction.Bind(category))
        editSub.Add(T("menu_delete_category"), DeleteCategoryMenuAction.Bind(category))
        sub.Add(T("menu_edit_category"), editSub)
        mainMenu.Add(category, sub)
    }

    if openUpward
        AddRootShortcutSection(mainMenu, false, shortcutEntries)
    if !openUpward
        AddFarRootActionsSection(mainMenu, false)

    StartMenuOutsideClickWatcher()
    try {
        mainMenu.Show(mx, my)
    } finally {
        StopMenuOutsideClickWatcher()
    }
}

; Handles no op.
NoOp(*) {
}

; Handles root new category menu action.
RootNewCategoryMenuAction(*) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    result := InputBox("Name for new category:", "New Category")
    if (result.Result != "OK")
        return

    name := Trim(result.Value)
    if (name = "") {
        MsgBox "Category name kan inte vara tomt."
        return
    }

    if _EntriesByCategory.Has(name) {
        MsgBox "Category finns redan: " name
        OpenCategoryEditor(name)
        return
    }

    _Categories.Push(name)
    _EntriesByCategory[name] := Map()
    _EntryOrderByCategory[name] := []

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    OpenCategoryEditor(name, "", true)
}

; Handles root entry editor menu action.
RootEntryEditorMenuAction(*) {
    TrayOpenEditorAction()
}

; Handles root close menu action.
RootCloseMenuAction(*) {
    ; Menyn stangs automatiskt nar en item klickas.
    return
}

; Handles quick new entry menu action.
QuickNewEntryMenuAction(category, *) {
    OpenQuickNewEntryDialog(category)
}

; Opens or shows open quick new entry dialog.
OpenQuickNewEntryDialog(category) {
    global _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    if !(_EntriesByCategory.Has(category) && _EntryOrderByCategory.Has(category)) {
        MsgBox "Okand kategori: " category
        return
    }

    quickGui := Gui("+AlwaysOnTop -MaximizeBox", "Quick New Entry - " category)
    quickGui.SetFont("s10", "Segoe UI")

    quickGui.AddText("x10 y10 w480", "Title")
    titleEdit := AddStandardBorderEdit(quickGui, 10, 28, 480, 24)
    quickGui.AddText("x10 y60 w480", "Content")
    contentEdit := AddStandardBorderEdit(quickGui, 10, 78, 480, 150, "Multi WantTab")

    btnSave := quickGui.AddButton("x300 y236 w90 h32", "Save")
    btnCancel := quickGui.AddButton("x400 y236 w90 h32", "Cancel")

    state := {
        gui: quickGui,
        category: category,
        titleEdit: titleEdit,
        contentEdit: contentEdit
    }

    btnSave.OnEvent("Click", QuickEntrySave.Bind(state))
    btnCancel.OnEvent("Click", QuickEntryCancel.Bind(state))
    quickGui.OnEvent("Close", QuickEntryCancel.Bind(state))
    quickGui.OnEvent("Escape", QuickEntryCancel.Bind(state))

    quickGui.Show("w500 h280")
    titleEdit.Focus()
}

; Adds an edit control with a consistent 1px black border.
; Use this for new editor text boxes to keep visual style aligned.
AddStandardBorderEdit(parentGui, x, y, w, h := 24, extraOpts := "") {
    parentGui.AddText("x" x " y" y " w" w " h" h " +0x7 Background000000")

    innerX := x + 1
    innerY := y + 1
    innerW := Max(1, w - 2)
    innerH := Max(1, h - 2)
    opts := "x" innerX " y" innerY " w" innerW " h" innerH " -0x800000 -E0x200 +BackgroundFFFFFF"
    if (extraOpts != "")
        opts .= " " extraOpts
    return parentGui.AddEdit(opts)
}

; Handles quick entry save.
QuickEntrySave(state, *) {
    global _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    category := state.category
    title := Trim(state.titleEdit.Value)
    content := state.contentEdit.Value

    if (title = "") {
        MsgBox "Title kan inte vara tom."
        return
    }

    entries := _EntriesByCategory[category]
    order := _EntryOrderByCategory[category]
    beforeExists := entries.Has(title)
    beforeContent := beforeExists ? entries[title] : ""

    if beforeExists {
        ans := MsgBox(
            "En entry med samma titel finns redan. Skriv over?",
            "Bekrafta overskrivning",
            "YesNo Icon?"
        )
        if (ans != "Yes")
            return
    } else {
        order.Push(title)
    }

    entries[title] := content

    changeType := beforeExists ? "edit" : "add"
    change := MakeEntryChange(changeType, category, title, beforeExists, beforeContent, category, title, true, content)
    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    try state.gui.Destroy()
}

; Handles quick entry cancel.
QuickEntryCancel(state, *) {
    try state.gui.Destroy()
}

; Handles paste snippet.
PasteSnippet(category, title, *) {
    global _EntriesByCategory, EnableRichText, _PendingPasteTarget

    if !_EntriesByCategory.Has(category) || !_EntriesByCategory[category].Has(title) {
        SoundBeep 1500
        return
    }

    target := _PendingPasteTarget
    _PendingPasteTarget := 0
    if !FocusPasteTarget(target) {
        ShowTransientToolTip(T("msg_paste_target_lost"))
        return
    }

    rawText := _EntriesByCategory[category][title]
    SetLastSelectedMenuEntry(category, title)
    if (EnableRichText)
        PasteRich(rawText, target)
    else
        PastePlain(ConvertMarkupToPlainText(rawText), target)
}

; Handles edit category menu action.
EditCategoryMenuAction(category, *) {
    OpenCategoryEditor(category)
}

; Handles new entry menu action.
NewEntryMenuAction(category, *) {
    OpenCategoryEditor(category, "", true)
}

; Handles rename category menu action.
RenameCategoryMenuAction(category, *) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    result := InputBox("New name for category '" category "':", "Rename Category",, category)
    if (result.Result != "OK")
        return

    newName := Trim(result.Value)
    if (newName = "")
        return
    if (newName = category)
        return

    if _EntriesByCategory.Has(newName) {
        MsgBox "Category finns redan: " newName
        return
    }

    idx := FindIndexInArray(_Categories, category)
    if !idx {
        MsgBox "Kunde inte hitta kategori: " category
        return
    }

    _Categories[idx] := newName
    _EntriesByCategory[newName] := _EntriesByCategory[category]
    _EntryOrderByCategory[newName] := _EntryOrderByCategory[category]
    _EntriesByCategory.Delete(category)
    _EntryOrderByCategory.Delete(category)

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    OpenCategoryEditor(newName)
}

; Deletes or removes delete category menu action.
DeleteCategoryMenuAction(category, *) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory, DefaultCategory
    global SnippetFile, SnippetEncoding, _EditorState

    if !_EntriesByCategory.Has(category) || !_EntryOrderByCategory.Has(category) {
        MsgBox "Okand kategori: " category
        return
    }

    entryCount := _EntryOrderByCategory[category].Length
    msg := "Delete category '" category "'?"
    if (entryCount > 0) {
        suffix := "ies."
        if (entryCount = 1)
            suffix := "y."
        msg .= "`n`nThis will also delete " entryCount " entr" suffix
    }

    ans := MsgBox(msg, "Confirm delete category", "YesNo Icon!")
    if (ans != "Yes")
        return

    idx := FindIndexInArray(_Categories, category)
    if idx
        _Categories.RemoveAt(idx)

    _EntriesByCategory.Delete(category)
    _EntryOrderByCategory.Delete(category)

    if (_Categories.Length = 0) {
        _Categories.Push(DefaultCategory)
        _EntriesByCategory[DefaultCategory] := Map()
        _EntryOrderByCategory[DefaultCategory] := []
    }

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    if IsObject(_EditorState) {
        try _EditorState.gui.Destroy()
        _EditorState := 0
    }

    OpenCategoryEditor(_Categories[1], "", false)
}

; Opens or shows open category editor.
OpenCategoryEditor(category, selectTitle := "", startNew := false) {
    global _EditorState, _EntryOrderByCategory, _EntriesByCategory, _Categories
    global ShowSelectedNearClick

    if !(_EntryOrderByCategory.Has(category) && _EntriesByCategory.Has(category)) {
        MsgBox "Okand kategori: " category
        return
    }

    if IsObject(_EditorState) {
        try _EditorState.gui.Destroy()
        _EditorState := 0
    }

    editorGui := Gui("+Resize +MinSize1040x560", "Feedback Editor - " category)
    editorGui.SetFont("s10", "Segoe UI")

    editorGui.AddGroupBox("x10 y8 w220 h540", "Categories")
    categoryList := editorGui.AddListBox("x22 y30 w196 h380", _Categories)
    btnCatRename := editorGui.AddButton("x22 y418 w95 h30", "Rename")
    btnCatDelete := editorGui.AddButton("x123 y418 w95 h30", "Delete")
    btnCatNew := editorGui.AddButton("x22 y454 w196 h30", T("menu_new_category"))
    editorGui.AddText("x22 y488 w196 h54", "Tip: Drag an entry onto a category to move it, or use Move in Entry Editor.")

    editorGui.AddGroupBox("x240 y8 w250 h540", "Entries")
    entryList := editorGui.AddListBox("x252 y30 w226 h470", _EntryOrderByCategory[category])
    chkNearClick := editorGui.AddCheckBox("x252 y506 w226 h28", T("editor_show_selected_near_click"))
    chkNearClick.Value := ShowSelectedNearClick ? 1 : 0

    editorGui.AddGroupBox("x500 y8 w530 h540", "Entry Editor")
    editorGui.AddText("x514 y30 w500", "Title")
    titleEdit := AddStandardBorderEdit(editorGui, 514, 48, 500, 24)
    editorGui.AddText("x514 y80 w500", "Content")
    contentEdit := AddStandardBorderEdit(editorGui, 514, 98, 500, 390, "Multi WantTab")
    editorGui.AddText("x514 y494 w500", "Tip: Drag inside entries list to reorder.")

    btnSave := editorGui.AddButton("x514 y514 w100 h28", "Save")
    btnNew := editorGui.AddButton("x622 y514 w110 h28", "New entry")
    btnDelete := editorGui.AddButton("x740 y514 w100 h28", "Delete")
    btnMove := editorGui.AddButton("x848 y514 w68 h28", T("editor_move"))
    btnClose := editorGui.AddButton("x924 y514 w90 h28", "Close")

    state := {
        currentCategory: category,
        gui: editorGui,
        categoryList: categoryList,
        entryList: entryList,
        chkNearClick: chkNearClick,
        titleEdit: titleEdit,
        contentEdit: contentEdit,
        currentTitle: "",
        suppressCategoryChange: false,
        inlineRename: 0
    }
    _EditorState := state

    categoryList.OnEvent("Change", EditorCategoryChange.Bind(state))
    entryList.OnEvent("Change", EditorSelectEntry.Bind(state))
    entryList.OnEvent("DoubleClick", EditorBeginInlineRename.Bind(state))
    chkNearClick.OnEvent("Click", EditorToggleNearClickEntry.Bind(state))
    btnCatRename.OnEvent("Click", EditorRenameCategory.Bind(state))
    btnCatDelete.OnEvent("Click", EditorDeleteCategory.Bind(state))
    btnCatNew.OnEvent("Click", EditorNewCategory.Bind(state))
    btnSave.OnEvent("Click", EditorSave.Bind(state))
    btnNew.OnEvent("Click", EditorNew.Bind(state))
    btnDelete.OnEvent("Click", EditorDelete.Bind(state))
    btnMove.OnEvent("Click", EditorMove.Bind(state))
    btnClose.OnEvent("Click", EditorClose.Bind(state))
    editorGui.OnEvent("Close", EditorClose.Bind(state))
    editorGui.OnEvent("Escape", EditorClose.Bind(state))

    editorGui.Show("w1040 h560")
    EditorLoadCategory(state, category, selectTitle, startNew)
}

; Handles editor category change.
EditorCategoryChange(state, ctrl, *) {
    if state.suppressCategoryChange
        return

    newCategory := ctrl.Text
    if (newCategory = "" || newCategory = state.currentCategory)
        return
    EditorLoadCategory(state, newCategory, "", false)
}

; Handles editor load category.
EditorLoadCategory(state, category, selectTitle := "", startNew := false) {
    global _Categories, _EntryOrderByCategory, _EntriesByCategory, _DragState

    if !(_EntryOrderByCategory.Has(category) && _EntriesByCategory.Has(category))
        return false

    EndInlineEntryRename(state, false, true)

    ; Rebuilding the list invalidates any pending drag state.
    _DragState := 0
    StopEntryDragVisual()

    state.currentCategory := category
    state.currentTitle := ""
    try state.gui.Title := "Feedback Editor - " category

    state.suppressCategoryChange := true
    try {
        catIdx := FindIndexInArray(_Categories, category)
        if catIdx
            state.categoryList.Choose(catIdx)
    } finally {
        state.suppressCategoryChange := false
    }

    existingCount := LB_GetCount(state.entryList.Hwnd)
    Loop existingCount
        state.entryList.Delete(1)
    order := _EntryOrderByCategory[category]
    if (order.Length > 0)
        state.entryList.Add(order)

    if startNew {
        EditorNew(state)
        return true
    }

    if (order.Length = 0) {
        EditorNew(state)
        return true
    }

    idx := 1
    if (selectTitle != "") {
        found := FindIndexInArray(order, selectTitle)
        if found
            idx := found
    }

    state.entryList.Choose(idx)
    EditorSelectEntry(state, state.entryList)
    return true
}

; Handles lb get count.
LB_GetCount(lbHwnd) {
    static LB_GETCOUNT := 0x018B
    return SendMessage(LB_GETCOUNT, 0, 0, , "ahk_id " lbHwnd)
}

; Returns a listbox item's rectangle in listbox client coordinates.
LB_GetItemRect(lbHwnd, idx, &x, &y, &w, &h) {
    static LB_GETITEMRECT := 0x0198
    rect := Buffer(16, 0)
    idx0 := idx - 1
    result := SendMessage(LB_GETITEMRECT, idx0, rect.Ptr, , "ahk_id " lbHwnd)
    if (result = -1 || result = 0xFFFFFFFF)
        return false

    left := NumGet(rect, 0, "Int")
    top := NumGet(rect, 4, "Int")
    right := NumGet(rect, 8, "Int")
    bottom := NumGet(rect, 12, "Int")
    x := left
    y := top
    w := right - left
    h := bottom - top
    return true
}

; Returns listbox item row height in pixels.
LB_GetItemHeight(lbHwnd) {
    static LB_GETITEMHEIGHT := 0x01A1
    return SendMessage(LB_GETITEMHEIGHT, 0, 0, , "ahk_id " lbHwnd)
}

; Handles editor rename category.
EditorRenameCategory(state, *) {
    RenameCategoryMenuAction(state.currentCategory)
}

; Handles editor delete category.
EditorDeleteCategory(state, *) {
    DeleteCategoryMenuAction(state.currentCategory)
}

; Handles editor new category.
EditorNewCategory(state, *) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    result := InputBox("Name for new category:", "New Category")
    if (result.Result != "OK")
        return

    name := Trim(result.Value)
    if (name = "") {
        SoundBeep 1200
        return
    }
    if _EntriesByCategory.Has(name) {
        ShowTransientToolTip("Category exists: " name)
        EditorLoadCategory(state, name, "", false)
        return
    }

    _Categories.Push(name)
    _EntriesByCategory[name] := Map()
    _EntryOrderByCategory[name] := []

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    EditorLoadCategory(state, name, "", true)
}

; Handles editor toggle near click entry.
EditorToggleNearClickEntry(state, ctrl, *) {
    global ShowSelectedNearClick
    if (ctrl.Value = 1) {
        if (state.currentTitle = "") {
            ctrl.Value := 0
            return
        }
        ShowSelectedNearClick := true
        SetSelectedMenuEntry(state.currentCategory, state.currentTitle)
        SaveSettings()
        return
    }

    if IsEntryPinned(state.currentCategory, state.currentTitle)
        SetSelectedMenuEntry("", "")
    ShowSelectedNearClick := false
    SaveSettings()
}

; Handles editor select entry.
EditorSelectEntry(state, ctrl, *) {
    global _EntriesByCategory

    title := ctrl.Text
    if (title = "")
        return

    state.currentTitle := title
    state.titleEdit.Value := title
    state.contentEdit.Value := _EntriesByCategory[state.currentCategory][title]
    state.chkNearClick.Value := IsEntryPinned(state.currentCategory, title) ? 1 : 0
}

; Starts inline rename from listbox double-click.
EditorBeginInlineRename(state, ctrl, *) {
    BeginInlineEntryRename(state)
}

; Begins inline rename over the selected entry row (Explorer-style F2).
BeginInlineEntryRename(state) {
    global _EntryOrderByCategory
    if !IsObject(state)
        return
    if IsObject(state.inlineRename)
        return

    category := state.currentCategory
    oldTitle := state.currentTitle
    if (oldTitle = "")
        return

    idx := FindIndexInArray(_EntryOrderByCategory[category], oldTitle)
    if !idx
        return

    if !LB_GetItemRect(state.entryList.Hwnd, idx, &rx, &ry, &rw, &rh)
        return

    sx := rx
    sy := ry
    ClientToScreenXY(state.entryList.Hwnd, &sx, &sy)
    ScreenToClientXY(state.gui.Hwnd, &sx, &sy)

    x := sx + 1
    y := sy + 1
    w := Max(30, rw - 2)
    h := Max(16, rh - 2)

    renameEdit := state.gui.AddEdit("x" x " y" y " w" w " h" h, oldTitle)
    renameEdit.OnEvent("LoseFocus", EditorInlineRenameLoseFocus.Bind(state))
    state.inlineRename := {edit: renameEdit, originalTitle: oldTitle, closing: false}

    renameEdit.Focus()
    ; Select all text.
    SendMessage(0x00B1, 0, -1, , "ahk_id " renameEdit.Hwnd) ; EM_SETSEL
}

; Commits inline rename when focus leaves the overlay edit.
EditorInlineRenameLoseFocus(state, ctrl, *) {
    EndInlineEntryRename(state, true)
}

; Finalizes inline rename and optionally commits title change.
EndInlineEntryRename(state, commit := false, forceCancel := false) {
    global _EntriesByCategory, _EntryOrderByCategory
    global _LastSelectedMenuCategory, _LastSelectedMenuTitle
    global SnippetFile, SnippetEncoding

    if !IsObject(state) || !IsObject(state.inlineRename)
        return

    r := state.inlineRename
    if r.closing
        return
    r.closing := true
    state.inlineRename := 0

    oldTitle := r.originalTitle
    newTitle := ""
    try newTitle := Trim(r.edit.Value)
    try r.edit.Destroy()

    if forceCancel || !commit
        return
    if (newTitle = "" || newTitle = oldTitle)
        return

    category := state.currentCategory
    if !_EntriesByCategory.Has(category) || !_EntriesByCategory[category].Has(oldTitle)
        return

    order := _EntryOrderByCategory[category]
    entries := _EntriesByCategory[category]
    beforeContent := entries[oldTitle]
    renameOverwrite := false

    if entries.Has(newTitle) {
        ans := MsgBox(
            "En entry med samma titel finns redan. Skriv over?",
            "Bekrafta overskrivning",
            "YesNo Icon?"
        )
        if (ans != "Yes")
            return
        idxExisting := FindIndexInArray(order, newTitle)
        if idxExisting
            order.RemoveAt(idxExisting)
        ; Skip per-entry metadata backup for rename-overwrite.
        renameOverwrite := true
    }

    idxOld := FindIndexInArray(order, oldTitle)
    if idxOld
        order[idxOld] := newTitle

    entries.Delete(oldTitle)
    if !FindIndexInArray(order, newTitle)
        order.Push(newTitle)
    entries[newTitle] := beforeContent

    if IsEntryPinned(category, oldTitle)
        SetSelectedMenuEntry(category, newTitle)
    if (_LastSelectedMenuCategory = category && _LastSelectedMenuTitle = oldTitle)
        SetLastSelectedMenuEntry(category, newTitle)

    change := 0
    if !renameOverwrite
        change := MakeEntryChange("edit", category, oldTitle, true, beforeContent, category, newTitle, true, beforeContent)

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    EditorLoadCategory(state, category, newTitle, false)
}

; Handles editor new.
EditorNew(state, *) {
    state.currentTitle := ""
    try state.entryList.Value := 0
    state.titleEdit.Value := ""
    state.contentEdit.Value := ""
    SetSelectedMenuEntry("", "")
    state.titleEdit.Focus()
}

; Handles editor save.
EditorSave(state, *) {
    global _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    category := state.currentCategory
    order := _EntryOrderByCategory[category]
    entries := _EntriesByCategory[category]
    oldTitle := state.currentTitle

    newTitle := Trim(state.titleEdit.Value)
    if (newTitle = "") {
        MsgBox "Title kan inte vara tom."
        return
    }
    newContent := state.contentEdit.Value
    beforeExists := false
    beforeTitle := ""
    beforeContent := ""
    if (oldTitle != "") {
        beforeTitle := oldTitle
        if entries.Has(oldTitle) {
            beforeExists := true
            beforeContent := entries[oldTitle]
        }
    } else {
        beforeTitle := newTitle
        if entries.Has(newTitle) {
            beforeExists := true
            beforeContent := entries[newTitle]
        }
    }
    change := 0
    renameOverwrite := false

    if (oldTitle != "") {
        if (oldTitle != newTitle) {
            if entries.Has(newTitle) {
                ans := MsgBox(
                    "En entry med samma titel finns redan. Skriv over?",
                    "Bekrafta overskrivning",
                    "YesNo Icon?"
                )
                if (ans != "Yes")
                    return

                idxExisting := FindIndexInArray(order, newTitle)
                if idxExisting
                    order.RemoveAt(idxExisting)
                ; Complex rename-overwrite case: skip per-entry backup.
                renameOverwrite := true
            }

            idxOld := FindIndexInArray(order, oldTitle)
            if idxOld
                order[idxOld] := newTitle

            if entries.Has(oldTitle)
                entries.Delete(oldTitle)
        }

        if !FindIndexInArray(order, newTitle)
            order.Push(newTitle)
        entries[newTitle] := newContent
    } else {
        if entries.Has(newTitle) {
            ans := MsgBox(
                "En entry med samma titel finns redan. Skriv over?",
                "Bekrafta overskrivning",
                "YesNo Icon?"
            )
            if (ans != "Yes")
                return
        } else {
            order.Push(newTitle)
        }
        entries[newTitle] := newContent
    }

    if !renameOverwrite
        change := MakeEntryChange(beforeExists ? "edit" : "add", category, beforeTitle, beforeExists, beforeContent, category, newTitle, true, newContent)

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    EditorLoadCategory(state, category, newTitle, false)
}

; Handles editor delete.
EditorDelete(state, *) {
    global _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    category := state.currentCategory
    title := state.currentTitle
    if (title = "") {
        SoundBeep 1200
        return
    }

    ans := MsgBox(
        "Radera entry '" title "' i kategorin '" category "'?",
        "Bekrafta radering",
        "YesNo Icon!"
    )
    if (ans != "Yes")
        return

    order := _EntryOrderByCategory[category]
    entries := _EntriesByCategory[category]
    beforeExists := entries.Has(title)
    beforeContent := beforeExists ? entries[title] : ""

    idx := FindIndexInArray(order, title)
    if idx
        order.RemoveAt(idx)
    if entries.Has(title)
        entries.Delete(title)
    SetSelectedMenuEntry("", "")

    change := MakeEntryChange("delete", category, title, beforeExists, beforeContent, category, title, false, "")
    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    if (order.Length > 0)
        EditorLoadCategory(state, category, order[1], false)
    else
        EditorLoadCategory(state, category, "", true)
}

; Handles editor move.
EditorMove(state, *) {
    global _EntriesByCategory
    global SnippetFile, SnippetEncoding

    sourceCategory := state.currentCategory
    title := state.currentTitle
    if (title = "") {
        SoundBeep 1200
        return
    }
    if !_EntriesByCategory.Has(sourceCategory) || !_EntriesByCategory[sourceCategory].Has(title) {
        SoundBeep 1500
        return
    }
    beforeContent := _EntriesByCategory[sourceCategory][title]

    targetCategory := PromptMoveTargetCategory(sourceCategory, title)
    if (targetCategory = "")
        return

    movedTitle := MoveEntryToCategory(sourceCategory, title, targetCategory)
    if (movedTitle = "") {
        SoundBeep 1500
        return
    }

    change := MakeEntryChange("edit", sourceCategory, title, true, beforeContent, targetCategory, movedTitle, true, beforeContent)
    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    EditorLoadCategory(state, targetCategory, movedTitle, false)
}

; Handles prompt move target category.
PromptMoveTargetCategory(sourceCategory, title) {
    global _Categories

    choices := []
    for _, c in _Categories {
        if (c != sourceCategory)
            choices.Push(c)
    }
    if (choices.Length = 0) {
        ShowTransientToolTip(T("msg_move_no_target_category"))
        return ""
    }

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", T("editor_move"))
    dlg.SetFont("s10", "Segoe UI")
    dlg.AddText("x12 y12 w320", T("msg_move_target_prompt"))
    ddl := dlg.AddDropDownList("x12 y34 w320 Choose1", choices)
    btnOk := dlg.AddButton("x176 y68 w74 h28", T("hotkey_dialog_save"))
    btnCancel := dlg.AddButton("x258 y68 w74 h28", T("hotkey_dialog_cancel"))

    selected := ""
    btnOk.OnEvent("Click", (*) => (selected := ddl.Text, dlg.Destroy()))
    btnCancel.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Escape", (*) => dlg.Destroy())

    dlg.Show("w344 h106")
    WinWaitClose("ahk_id " dlg.Hwnd)
    return selected
}

; Handles editor close.
EditorClose(state, *) {
    global _EditorState, _DragState
    EndInlineEntryRename(state, false, true)
    try state.gui.Destroy()
    _EditorState := 0
    _DragState := 0
    StopEntryDragVisual()
}

; Handles editor on l button down.
Editor_OnLButtonDown(wParam, lParam, msg, hwnd) {
    global _EditorState, _DragState, _EntryOrderByCategory, _Categories

    if !IsObject(_EditorState)
        return
    isEntryList := (hwnd = _EditorState.entryList.Hwnd)
    isCategoryList := (hwnd = _EditorState.categoryList.Hwnd)
    if !(isEntryList || isCategoryList)
        return

    GetMouseScreenPos(&startScreenX, &startScreenY)

    idx := LB_ItemFromPoint(hwnd, lParam)
    if (idx < 1)
        return

    if isEntryList {
        category := _EditorState.currentCategory
        if !_EntryOrderByCategory.Has(category)
            return
        order := _EntryOrderByCategory[category]
        if (idx > order.Length)
            return

        _DragState := {
            active: true,
            dragging: false,
            kind: "entry",
            sourceCategory: category,
            sourceIndex: idx,
            sourceTitle: order[idx],
            sourceLabel: order[idx],
            sourceListHwnd: hwnd,
            startClientX: LParamLowWordSigned(lParam),
            startClientY: LParamHighWordSigned(lParam),
            startScreenX: startScreenX,
            startScreenY: startScreenY,
            thresholdPx: 6
        }
    } else {
        if (idx > _Categories.Length)
            return
        sourceCategory := _Categories[idx]
        _DragState := {
            active: true,
            dragging: false,
            kind: "category",
            sourceCategory: sourceCategory,
            sourceIndex: idx,
            sourceLabel: sourceCategory,
            sourceListHwnd: hwnd,
            startClientX: LParamLowWordSigned(lParam),
            startClientY: LParamHighWordSigned(lParam),
            startScreenX: startScreenX,
            startScreenY: startScreenY,
            thresholdPx: 6
        }
    }
    SetTimer(UpdateEntryDragVisual, GetDragVisualTimerIntervalMs())
}

; Handles editor on l button up.
Editor_OnLButtonUp(wParam, lParam, msg, hwnd) {
    global _EditorState, _DragState
    global _Categories, _EntryOrderByCategory, _EntriesByCategory
    global SnippetFile, SnippetEncoding

    if !IsObject(_DragState) || !_DragState.active
        return
    if !IsObject(_EditorState) {
        _DragState := 0
        StopEntryDragVisual()
        return
    }
    if (!_DragState.HasOwnProp("dragging") || !_DragState.dragging) {
        ; Plain click selection, not a drag/drop action.
        _DragState := 0
        StopEntryDragVisual()
        return
    }

    moved := false
    change := 0
    dragKind := _DragState.HasOwnProp("kind") ? _DragState.kind : "entry"
    reopenCategory := _EditorState.currentCategory
    reopenTitle := _EditorState.currentTitle
    if (dragKind = "entry") {
        reopenCategory := _DragState.sourceCategory
        reopenTitle := _DragState.sourceTitle
    }
    hoverCtrl := 0
    mx := 0
    my := 0
    GetMouseScreenPos(&mx, &my)
    MouseGetPos , , , &hoverCtrl, 2

    if (dragKind = "entry") {
        if (hoverCtrl = _EditorState.categoryList.Hwnd) {
            ; Drop on category list moves the entry across categories.
            cx := mx
            cy := my
            ScreenToClientXY(hoverCtrl, &cx, &cy)
            catIdx := LB_ItemFromXY(hoverCtrl, cx, cy)
            if (catIdx >= 1 && catIdx <= _Categories.Length) {
                targetCategory := _Categories[catIdx]
                beforeContent := _EntriesByCategory[_DragState.sourceCategory][_DragState.sourceTitle]
                movedTitle := MoveEntryToCategory(_DragState.sourceCategory, _DragState.sourceTitle, targetCategory)
                if (movedTitle != "") {
                    moved := true
                    change := MakeEntryChange("edit", _DragState.sourceCategory, _DragState.sourceTitle, true, beforeContent, targetCategory, movedTitle, true, beforeContent)
                    reopenCategory := targetCategory
                    reopenTitle := movedTitle
                }
            }
        } else if (hoverCtrl = _EditorState.entryList.Hwnd || hwnd = _EditorState.entryList.Hwnd) {
            ; Drop on entries list reorders inside the same category.
            if (hoverCtrl = _EditorState.entryList.Hwnd) {
                cx := mx
                cy := my
                ScreenToClientXY(hoverCtrl, &cx, &cy)
                targetIdx := LB_ItemFromXY(hoverCtrl, cx, cy)
            } else {
                targetIdx := LB_ItemFromPoint(hwnd, lParam)
            }
            if (targetIdx < 1)
                targetIdx := _EntryOrderByCategory[_DragState.sourceCategory].Length + 1
            moved := MoveEntryWithinCategory(_DragState.sourceCategory, _DragState.sourceTitle, targetIdx)
        }
    } else if (dragKind = "category") {
        if (hoverCtrl = _EditorState.categoryList.Hwnd || hwnd = _EditorState.categoryList.Hwnd) {
            if (hoverCtrl = _EditorState.categoryList.Hwnd) {
                cx := mx
                cy := my
                ScreenToClientXY(hoverCtrl, &cx, &cy)
                targetIdx := LB_ItemFromXY(hoverCtrl, cx, cy)
            } else {
                targetIdx := LB_ItemFromPoint(hwnd, lParam)
            }
            if (targetIdx < 1)
                targetIdx := _Categories.Length + 1
            moved := MoveCategoryWithinList(_DragState.sourceCategory, targetIdx)
            reopenCategory := _DragState.sourceCategory
        }
    }

    if moved {
        if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
            MsgBox "Kunde inte spara till fil:`n" SnippetFile
        } else {
            EditorLoadCategory(_EditorState, reopenCategory, reopenTitle, false)
        }
    }

    _DragState := 0
    StopEntryDragVisual()
}

; Handles right-click context menu for entry actions in the entries list.
Editor_OnContextMenu(wParam, lParam, msg, hwnd) {
    global _EditorState, _EntryOrderByCategory

    if !IsObject(_EditorState)
        return

    ctrlHwnd := wParam ? wParam : hwnd
    if (ctrlHwnd != _EditorState.entryList.Hwnd)
        return

    category := _EditorState.currentCategory
    if !_EntryOrderByCategory.Has(category)
        return
    order := _EntryOrderByCategory[category]
    if (order.Length = 0)
        return

    idx := 0
    sx := 0
    sy := 0
    if (lParam = -1) {
        idx := FindIndexInArray(order, _EditorState.currentTitle)
        if !idx
            idx := _EditorState.entryList.Value
        if (idx < 1 || idx > order.Length)
            return

        if LB_GetItemRect(ctrlHwnd, idx, &rx, &ry, &rw, &rh) {
            sx := rx + (rw // 2)
            sy := ry + (rh // 2)
            ClientToScreenXY(ctrlHwnd, &sx, &sy)
        } else {
            GetMouseScreenPos(&sx, &sy)
        }
    } else {
        sx := LParamLowWordSigned(lParam)
        sy := LParamHighWordSigned(lParam)
        cx := sx
        cy := sy
        ScreenToClientXY(ctrlHwnd, &cx, &cy)
        idx := LB_ItemFromXY(ctrlHwnd, cx, cy)
        if (idx < 1 || idx > order.Length)
            return
    }

    title := order[idx]
    _EditorState.entryList.Choose(idx)
    EditorSelectEntry(_EditorState, _EditorState.entryList)
    EditorShowEntryContextMenu(_EditorState, category, title, sx, sy)
    return 0
}

; Shows context menu for entry-level actions.
EditorShowEntryContextMenu(state, category, title, sx, sy) {
    global _Categories

    if (title = "")
        return
    EndInlineEntryRename(state, false, true)

    ctx := Menu()
    ctx.Add(T("menu_rename"), EditorContextRenameEntry.Bind(state, category, title))

    moveSub := Menu()
    hasTarget := false
    for _, c in _Categories {
        if (c = category)
            continue
        hasTarget := true
        moveSub.Add(c, EditorContextMoveEntry.Bind(state, category, title, c))
    }
    if !hasTarget
        moveSub.Add(T("msg_move_no_target_category"), NoOp)

    ctx.Add(T("menu_move_to"), moveSub)
    ctx.Show(sx, sy)
}

; Starts inline rename for a specific entry.
EditorContextRenameEntry(state, category, title, *) {
    global _EntryOrderByCategory

    if (state.currentCategory != category)
        EditorLoadCategory(state, category, title, false)

    if !_EntryOrderByCategory.Has(category)
        return
    idx := FindIndexInArray(_EntryOrderByCategory[category], title)
    if !idx
        return

    state.entryList.Choose(idx)
    EditorSelectEntry(state, state.entryList)
    BeginInlineEntryRename(state)
}

; Moves a specific entry to another category from context menu.
EditorContextMoveEntry(state, sourceCategory, title, targetCategory, *) {
    global _EntriesByCategory
    global SnippetFile, SnippetEncoding

    if (sourceCategory = targetCategory)
        return
    if !_EntriesByCategory.Has(sourceCategory) || !_EntriesByCategory[sourceCategory].Has(title)
        return

    beforeContent := _EntriesByCategory[sourceCategory][title]
    movedTitle := MoveEntryToCategory(sourceCategory, title, targetCategory)
    if (movedTitle = "")
        return

    change := MakeEntryChange("edit", sourceCategory, title, true, beforeContent, targetCategory, movedTitle, true, beforeContent)
    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding, change, true) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }
    EditorLoadCategory(state, targetCategory, movedTitle, false)
}

; Initializes or controls start entry drag visual.
StartEntryDragVisual(title) {
    global _DragGhost, _EditorState, _DragState
    StopEntryDragVisual()

    rowWMax := 220
    rowHMax := 20
    listHwnd := 0
    if IsObject(_DragState) && _DragState.HasOwnProp("sourceListHwnd")
        listHwnd := _DragState.sourceListHwnd
    if (!listHwnd && IsObject(_EditorState))
        listHwnd := _EditorState.entryList.Hwnd

    if listHwnd {
        GetControlClientSize(listHwnd, &cw, &ch)
        if (cw > 20)
            rowWMax := Max(80, cw - 10)
        ih := LB_GetItemHeight(listHwnd)
        if (ih >= 12 && ih <= 64)
            rowHMax := Max(12, ih - 2)
    }
    fixedTextW := MeasureTextWidthPx("0123456789", "Segoe UI", 10)
    textH := MeasureTextHeightPx("Ag", "Segoe UI", 10)
    rowW := Max(64, fixedTextW + 14)
    rowH := Max(12, textH + 2)
    if (rowW > rowWMax)
        rowW := rowWMax
    if (rowH > rowHMax)
        rowH := rowHMax

    ghostGui := Gui("-Caption -DPIScale +ToolWindow +AlwaysOnTop +Border +E0x20")
    ghostGui.SetFont("s10", "Segoe UI")
    ghostGui.BackColor := "FFFFFF"
    ghostGui.MarginX := 0
    ghostGui.MarginY := 0
    innerW := Max(1, rowW - 8)
    innerH := Max(1, rowH + 1)
    ; Nudge text up 1px for visual balance (Segoe UI metrics often look low in small bordered boxes).
    ghostGui.AddText("x4 y-1 w" innerW " h" innerH " +0x420C c000000", title)

    gx := 0
    gy := 0
    GetMouseScreenPos(&mx, &my)
    gx := mx + 8
    gy := my + 8
    ghostGui.Show("NA x" gx " y" gy " w" rowW " h" rowH)
    ApplyDragGhostTransparency(ghostGui.Hwnd, GetDragGhostAlpha())

    _DragGhost := {gui: ghostGui, hwnd: ghostGui.Hwnd, x: gx, y: gy}
    StartHighResDragTimer()
    SetTimer(UpdateEntryDragVisual, GetDragVisualTimerIntervalMs())
}

; Updates update entry drag visual.
UpdateEntryDragVisual() {
    global _DragState, _DragGhost

    if !IsObject(_DragState) || !_DragState.active {
        StopEntryDragVisual()
        return
    }
    if !GetKeyState("LButton", "P") {
        _DragState := 0
        StopEntryDragVisual()
        return
    }

    GetMouseScreenPos(&mx, &my)
    if (!_DragState.HasOwnProp("dragging") || !_DragState.dragging) {
        threshold := _DragState.HasOwnProp("thresholdPx") ? _DragState.thresholdPx : 6
        if (Abs(mx - _DragState.startScreenX) < threshold && Abs(my - _DragState.startScreenY) < threshold)
            return
        _DragState.dragging := true
        label := _DragState.HasOwnProp("sourceLabel") ? _DragState.sourceLabel : (_DragState.HasOwnProp("sourceTitle") ? _DragState.sourceTitle : "")
        StartEntryDragVisual(label)
        return
    }
    if !IsObject(_DragGhost)
        return

    gx := mx + 8
    gy := my + 8
    MoveEntryDragVisualTo(gx, gy)
}

; Initializes or controls stop entry drag visual.
StopEntryDragVisual() {
    global _DragGhost
    SetTimer(UpdateEntryDragVisual, 0)
    StopHighResDragTimer()
    if IsObject(_DragGhost)
        try _DragGhost.gui.Destroy()
    _DragGhost := 0
}

; Moves the drag ghost window without triggering full redraw each frame.
MoveEntryDragVisualTo(x, y) {
    global _DragGhost
    if !IsObject(_DragGhost)
        return
    if (_DragGhost.x = x && _DragGhost.y = y)
        return

    _DragGhost.x := x
    _DragGhost.y := y
    ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
    DllCall("SetWindowPos"
        , "Ptr", _DragGhost.hwnd
        , "Ptr", 0
        , "Int", x
        , "Int", y
        , "Int", 0
        , "Int", 0
        , "UInt", 0x0015)
}

; Returns drag visual update interval derived from current refresh rate.
GetDragVisualTimerIntervalMs() {
    hz := GetRefreshRateHzForCursorWindow()
    if (hz < 30 || hz > 360)
        hz := 120

    ms := Round(1000 / hz)
    if (ms < 4)
        ms := 4
    if (ms > 17)
        ms := 17
    return ms
}

; Returns refresh rate for the display containing the cursor window.
GetRefreshRateHzForCursorWindow() {
    targetHwnd := 0
    MouseGetPos , , &targetHwnd

    hdc := 0
    if targetHwnd
        hdc := DllCall("GetDC", "Ptr", targetHwnd, "Ptr")
    if !hdc {
        targetHwnd := 0
        hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    }
    if !hdc
        return 0

    hz := DllCall("GetDeviceCaps", "Ptr", hdc, "Int", 116, "Int") ; VREFRESH
    DllCall("ReleaseDC", "Ptr", targetHwnd, "Ptr", hdc)

    if (hz <= 1 || hz = 0xFFFFFFFF)
        return 0
    return hz
}

; Returns drag ghost alpha similar to standard Windows drag translucency.
GetDragGhostAlpha() {
    return 208
}

; Applies translucency to the drag ghost with WinSetTransparent fallback.
ApplyDragGhostTransparency(hwnd, alpha := 208) {
    if !hwnd
        return
    if (alpha < 40)
        alpha := 40
    if (alpha > 255)
        alpha := 255

    didApply := false
    try {
        WinSetTransparent(alpha, "ahk_id " hwnd)
        currentAlpha := ""
        try currentAlpha := WinGetTransparent("ahk_id " hwnd)
        if (currentAlpha != "" && currentAlpha != "Off")
            didApply := true
    }
    if didApply
        return

    WS_EX_LAYERED := 0x00080000
    GWL_EXSTYLE := -20
    if (A_PtrSize = 8) {
        exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        if !(exStyle & WS_EX_LAYERED)
            DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle | WS_EX_LAYERED, "Ptr")
    } else {
        exStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "UInt")
        if !(exStyle & WS_EX_LAYERED)
            DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "UInt", exStyle | WS_EX_LAYERED, "UInt")
    }

    ; LWA_ALPHA = 0x2
    DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", alpha, "UInt", 0x2)
}

; Handles editor on key down.
Editor_OnKeyDown(wParam, lParam, msg, hwnd) {
    global _EditorState

    if !IsObject(_EditorState)
        return
    targetCtrlHwnd := hwnd
    if (hwnd = _EditorState.gui.Hwnd) {
        focusedCtrl := ""
        try focusedCtrl := ControlGetFocus("ahk_id " _EditorState.gui.Hwnd)
        if (focusedCtrl != "") {
            try targetCtrlHwnd := ControlGetHwnd(focusedCtrl, "ahk_id " _EditorState.gui.Hwnd)
        }
    }

    ; Inline rename keys.
    if IsObject(_EditorState.inlineRename) {
        renameHwnd := _EditorState.inlineRename.edit.Hwnd
        if (targetCtrlHwnd = renameHwnd) {
            if (wParam = 0x0D) { ; Enter
                EndInlineEntryRename(_EditorState, true)
                return 0
            }
            if (wParam = 0x1B) { ; Escape
                EndInlineEntryRename(_EditorState, false, true)
                return 0
            }
        }
    }

    ; Explorer-style rename in entries list.
    if (targetCtrlHwnd = _EditorState.entryList.Hwnd && wParam = 0x71) { ; F2
        BeginInlineEntryRename(_EditorState)
        return 0
    }

    if !GetKeyState("Ctrl", "P")
        return
    if GetKeyState("Alt", "P")
        return

    isEditorTextCtrl := (targetCtrlHwnd = _EditorState.titleEdit.Hwnd || targetCtrlHwnd = _EditorState.contentEdit.Hwnd)
    if !isEditorTextCtrl
        return

    vk := wParam
    if (vk = 0x08) { ; VK_BACK
        DeleteWordLeftInEdit(targetCtrlHwnd)
        return 0
    }
}

; Deletes or removes delete word left in edit.
DeleteWordLeftInEdit(ctrlHwnd) {
    static EM_GETSEL := 0x00B0
    static EM_SETSEL := 0x00B1

    text := ""
    try text := ControlGetText("", "ahk_id " ctrlHwnd)
    textLen := StrLen(text)

    sel := SendMessage(EM_GETSEL, 0, 0, , "ahk_id " ctrlHwnd)
    selStart := sel & 0xFFFF
    selEnd := (sel >> 16) & 0xFFFF
    if (selStart < 0)
        selStart := 0
    if (selEnd < 0)
        selEnd := 0
    if (selStart > textLen)
        selStart := textLen
    if (selEnd > textLen)
        selEnd := textLen

    if (selStart != selEnd) {
        deleteStart := Min(selStart, selEnd)
        deleteEnd := Max(selStart, selEnd)
    } else {
        pos := selStart
        deleteStart := FindWordBoundaryLeft(text, pos)
        deleteEnd := pos
    }

    if (deleteEnd <= deleteStart)
        return

    newText := SubStr(text, 1, deleteStart) . SubStr(text, deleteEnd + 1)
    ControlSetText(newText, "", "ahk_id " ctrlHwnd)
    SendMessage(EM_SETSEL, deleteStart, deleteStart, , "ahk_id " ctrlHwnd)
}

; Returns or computes find word boundary left.
FindWordBoundaryLeft(text, pos) {
    if (pos <= 0)
        return 0
    textLen := StrLen(text)
    if (pos > textLen)
        pos := textLen

    left := SubStr(text, 1, pos)

    ; 1) Delete trailing whitespace cluster.
    if RegExMatch(left, "\s+$", &m)
        return pos - StrLen(m[0])
    ; 2) Delete trailing word characters.
    if RegExMatch(left, "[\p{L}\p{N}_]+$", &m)
        return pos - StrLen(m[0])
    ; 3) Delete trailing punctuation/symbol cluster.
    if RegExMatch(left, "[^\s\p{L}\p{N}_]+$", &m)
        return pos - StrLen(m[0])

    return Max(0, pos - 1)
}

; Checks whether is word char.
IsWordChar(ch) {
    return RegExMatch(ch, "[\p{L}\p{N}_]")
}

; Handles screen to client xy.
ScreenToClientXY(hwnd, &x, &y) {
    pt := Buffer(8, 0)
    NumPut("Int", x, pt, 0)
    NumPut("Int", y, pt, 4)
    DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}

; Converts client coordinates to screen coordinates.
ClientToScreenXY(hwnd, &x, &y) {
    pt := Buffer(8, 0)
    NumPut("Int", x, pt, 0)
    NumPut("Int", y, pt, 4)
    DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}

; Handles lb item from point.
LB_ItemFromPoint(lbHwnd, lParam) {
    static LB_ITEMFROMPOINT := 0x01A9
    res := SendMessage(LB_ITEMFROMPOINT, 0, lParam, , "ahk_id " lbHwnd)
    idx0 := res & 0xFFFF
    outside := (res >> 16) & 0xFFFF
    if outside
        return 0
    return idx0 + 1
}

; Handles lb item from xy.
LB_ItemFromXY(lbHwnd, x, y) {
    lParam := (x & 0xFFFF) | ((y & 0xFFFF) << 16)
    return LB_ItemFromPoint(lbHwnd, lParam)
}

; Reads cursor position in screen coordinates.
GetMouseScreenPos(&x, &y) {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}

; Reads a control's client size in pixels.
GetControlClientSize(hwnd, &w, &h) {
    rect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect, "Int")
        return (w := 0, h := 0)
    left := NumGet(rect, 0, "Int")
    top := NumGet(rect, 4, "Int")
    right := NumGet(rect, 8, "Int")
    bottom := NumGet(rect, 12, "Int")
    w := right - left
    h := bottom - top
}

; Measures text width in pixels for a given font.
MeasureTextWidthPx(text, fontName := "Segoe UI", fontSize := 10) {
    if (text = "")
        return 0

    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    if !hdc
        return StrLen(text) * 7

    dpiY := DllCall("GetDeviceCaps", "Ptr", hdc, "Int", 90, "Int") ; LOGPIXELSY
    fontHeight := -DllCall("MulDiv", "Int", fontSize, "Int", dpiY, "Int", 72, "Int")
    hFont := DllCall("CreateFontW"
        , "Int", fontHeight
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "Int", 400
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "WStr", fontName
        , "Ptr")

    oldObj := 0
    if hFont
        oldObj := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

    sz := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "Ptr", hdc, "WStr", text, "Int", StrLen(text), "Ptr", sz)
    width := NumGet(sz, 0, "Int")

    if oldObj
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldObj, "Ptr")
    if hFont
        DllCall("DeleteObject", "Ptr", hFont)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)

    return width
}

; Measures text height in pixels for a given font.
MeasureTextHeightPx(sampleText := "Ag", fontName := "Segoe UI", fontSize := 10) {
    if (sampleText = "")
        sampleText := "Ag"

    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    if !hdc
        return fontSize + 4

    dpiY := DllCall("GetDeviceCaps", "Ptr", hdc, "Int", 90, "Int") ; LOGPIXELSY
    fontHeight := -DllCall("MulDiv", "Int", fontSize, "Int", dpiY, "Int", 72, "Int")
    hFont := DllCall("CreateFontW"
        , "Int", fontHeight
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "Int", 400
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "UInt", 0
        , "WStr", fontName
        , "Ptr")

    oldObj := 0
    if hFont
        oldObj := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

    sz := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "Ptr", hdc, "WStr", sampleText, "Int", StrLen(sampleText), "Ptr", sz)
    height := NumGet(sz, 4, "Int")

    if oldObj
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldObj, "Ptr")
    if hFont
        DllCall("DeleteObject", "Ptr", hFont)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)

    return height
}

; Enables high-resolution timer while drag visual is active.
StartHighResDragTimer() {
    global _DragHighResTimer
    if (_DragHighResTimer)
        return
    if (DllCall("winmm\timeBeginPeriod", "UInt", 1, "UInt") = 0)
        _DragHighResTimer := true
}

; Restores default timer resolution.
StopHighResDragTimer() {
    global _DragHighResTimer
    if !_DragHighResTimer
        return
    DllCall("winmm\timeEndPeriod", "UInt", 1, "UInt")
    _DragHighResTimer := false
}

; Converts LPARAM low word to signed 16-bit coordinate.
LParamLowWordSigned(v) {
    n := v & 0xFFFF
    return (n >= 0x8000) ? (n - 0x10000) : n
}

; Converts LPARAM high word to signed 16-bit coordinate.
LParamHighWordSigned(v) {
    n := (v >> 16) & 0xFFFF
    return (n >= 0x8000) ? (n - 0x10000) : n
}

; Reorders categories in the global category list.
MoveCategoryWithinList(category, targetIdx) {
    global _Categories

    srcIdx := FindIndexInArray(_Categories, category)
    if !srcIdx
        return false

    maxTarget := _Categories.Length + 1
    if (targetIdx < 1)
        targetIdx := 1
    if (targetIdx > maxTarget)
        targetIdx := maxTarget

    if (srcIdx = targetIdx)
        return false

    _Categories.RemoveAt(srcIdx)
    if (srcIdx < targetIdx)
        targetIdx -= 1
    if (targetIdx < 1)
        targetIdx := 1
    if (targetIdx > _Categories.Length + 1)
        targetIdx := _Categories.Length + 1
    _Categories.InsertAt(targetIdx, category)
    return true
}

; Moves or copies move entry within category.
MoveEntryWithinCategory(category, title, targetIdx) {
    global _EntryOrderByCategory

    if !_EntryOrderByCategory.Has(category)
        return false

    order := _EntryOrderByCategory[category]
    srcIdx := FindIndexInArray(order, title)
    if !srcIdx
        return false

    maxTarget := order.Length + 1
    if (targetIdx < 1)
        targetIdx := 1
    if (targetIdx > maxTarget)
        targetIdx := maxTarget

    if (srcIdx = targetIdx)
        return false

    order.RemoveAt(srcIdx)
    if (srcIdx < targetIdx)
        targetIdx -= 1
    if (targetIdx < 1)
        targetIdx := 1
    if (targetIdx > order.Length + 1)
        targetIdx := order.Length + 1
    order.InsertAt(targetIdx, title)
    return true
}

; Moves or copies move entry to category.
MoveEntryToCategory(sourceCategory, title, targetCategory) {
    global _EntriesByCategory, _EntryOrderByCategory

    if (sourceCategory = targetCategory)
        return ""
    if !_EntriesByCategory.Has(sourceCategory) || !_EntriesByCategory.Has(targetCategory)
        return ""
    if !_EntriesByCategory[sourceCategory].Has(title)
        return ""

    srcOrder := _EntryOrderByCategory[sourceCategory]
    srcEntries := _EntriesByCategory[sourceCategory]
    dstOrder := _EntryOrderByCategory[targetCategory]
    dstEntries := _EntriesByCategory[targetCategory]

    content := srcEntries[title]
    srcEntries.Delete(title)

    idx := FindIndexInArray(srcOrder, title)
    if idx
        srcOrder.RemoveAt(idx)

    newTitle := title
    if dstEntries.Has(newTitle)
        newTitle := MakeUniqueEntryTitle(newTitle, dstOrder)
    dstEntries[newTitle] := content
    dstOrder.Push(newTitle)

    if IsEntryPinned(sourceCategory, title)
        SetSelectedMenuEntry(targetCategory, newTitle)

    return newTitle
}

; Handles paste rich.
PasteRich(rawText, target := 0) {
    plainText := ConvertMarkupToPlainText(rawText)
    htmlFragment := ConvertMarkupToHtml(rawText)

    clipSaved := ""
    try clipSaved := ClipboardAll()

    ok := SetClipboardTextAndHtml(plainText, htmlFragment)
    if ok {
        SendPasteToTarget(target)
        Sleep 250
    } else {
        A_Clipboard := ""
        A_Clipboard := plainText
        SendPasteToTarget(target)
        Sleep 250
    }

    try A_Clipboard := clipSaved
}

; Handles paste plain.
PastePlain(text, target := 0) {
    clipSaved := ""
    try clipSaved := ClipboardAll()

    A_Clipboard := ""
    A_Clipboard := text
    SendPasteToTarget(target)
    Sleep 250
    try A_Clipboard := clipSaved
}

; Handles convert markup to plain text.
ConvertMarkupToPlainText(text) {
    global EnableLinkMarkup

    out := text
    if EnableLinkMarkup
        out := ReplaceLinks(out, "markdown")
    return out
}

; Handles convert markup to html.
ConvertMarkupToHtml(text) {
    global EnableLinkMarkup

    html := EscapeHtml(text)
    if EnableLinkMarkup
        html := ReplaceLinks(html, "html")

    html := RegExReplace(html, "(?<!\*)\*([^*\r\n]+)\*(?!\*)", "<i>$1</i>")

    html := StrReplace(html, "`r`n", "`n")
    html := StrReplace(html, "`r", "`n")
    html := StrReplace(html, "`n", "<br>")
    return html
}

; Handles replace links.
ReplaceLinks(text, mode) {
    pattern := "([^\s\[\]\r\n]+)\[((?:https?://|mailto:|www\.)[^\]\r\n]+)\]"
    pos := 1
    out := ""

    while (matchPos := RegExMatch(text, pattern, &m, pos)) {
        out .= SubStr(text, pos, matchPos - pos)

        display := m[1]
        url := NormalizeUrl(m[2])

        if (mode = "html") {
            href := EscapeHtmlAttribute(url)
            out .= Format('<a href="{1}">{2}</a>', href, display)
        } else {
            out .= "[" display "](" url ")"
        }

        pos := matchPos + StrLen(m[0])
    }

    out .= SubStr(text, pos)
    return out
}

; Handles normalize url.
NormalizeUrl(url) {
    if RegExMatch(url, "i)^www\.")
        return "https://" url
    return url
}

; Handles escape html.
EscapeHtml(text) {
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    text := StrReplace(text, ">", "&gt;")
    return text
}

; Handles escape html attribute.
EscapeHtmlAttribute(text) {
    text := EscapeHtml(text)
    text := StrReplace(text, Chr(34), "&quot;")
    return text
}

; Sets or applies set clipboard text and html.
SetClipboardTextAndHtml(plainText, htmlFragment) {
    htmlFmt := DllCall("RegisterClipboardFormat", "Str", "HTML Format", "UInt")
    if !htmlFmt
        return false

    htmlPackage := BuildCFHtml(htmlFragment)

    hText := 0
    hHtml := 0

    if !AllocGlobalFromString(plainText, "UTF-16", &hText)
        return false

    if !AllocGlobalFromString(htmlPackage, "UTF-8", &hHtml) {
        DllCall("GlobalFree", "Ptr", hText)
        return false
    }

    if !OpenClipboardWithRetry() {
        DllCall("GlobalFree", "Ptr", hText)
        DllCall("GlobalFree", "Ptr", hHtml)
        return false
    }

    success := false
    DllCall("EmptyClipboard")

    if DllCall("SetClipboardData", "UInt", 13, "Ptr", hText, "Ptr") {
        hText := 0
        if DllCall("SetClipboardData", "UInt", htmlFmt, "Ptr", hHtml, "Ptr") {
            hHtml := 0
            success := true
        }
    }

    DllCall("CloseClipboard")
    if hText
        DllCall("GlobalFree", "Ptr", hText)
    if hHtml
        DllCall("GlobalFree", "Ptr", hHtml)

    return success
}

; Opens or shows open clipboard with retry.
OpenClipboardWithRetry(retries := 10, delayMs := 30) {
    Loop retries {
        if DllCall("OpenClipboard", "Ptr", 0)
            return true
        Sleep delayMs
    }
    return false
}

; Handles alloc global from string.
AllocGlobalFromString(text, encoding, &hMem) {
    hMem := 0
    if (encoding = "UTF-16")
        bytes := StrPut(text, "UTF-16") * 2
    else
        bytes := StrPut(text, encoding)

    hMem := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")
    if !hMem
        return false

    pMem := DllCall("GlobalLock", "Ptr", hMem, "Ptr")
    if !pMem {
        DllCall("GlobalFree", "Ptr", hMem)
        hMem := 0
        return false
    }

    StrPut(text, pMem, encoding)
    DllCall("GlobalUnlock", "Ptr", hMem)
    return true
}

; Creates or builds build cf html.
BuildCFHtml(fragmentHtml) {
    prefix := "<html><body><!--StartFragment-->"
    suffix := "<!--EndFragment--></body></html>"
    full := prefix fragmentHtml suffix

    header := "Version:1.0`r`n"
    header .= "StartHTML:0000000000`r`n"
    header .= "EndHTML:0000000000`r`n"
    header .= "StartFragment:0000000000`r`n"
    header .= "EndFragment:0000000000`r`n"

    startHTML := Utf8ByteLen(header)
    startFragment := startHTML + Utf8ByteLen(prefix)
    endFragment := startFragment + Utf8ByteLen(fragmentHtml)
    endHTML := startHTML + Utf8ByteLen(full)

    finalHeader := "Version:1.0`r`n"
    finalHeader .= "StartHTML:" Format("{:010}", startHTML) "`r`n"
    finalHeader .= "EndHTML:" Format("{:010}", endHTML) "`r`n"
    finalHeader .= "StartFragment:" Format("{:010}", startFragment) "`r`n"
    finalHeader .= "EndFragment:" Format("{:010}", endFragment) "`r`n"

    return finalHeader full
}

; Handles utf 8 byte len.
Utf8ByteLen(text) {
    return StrPut(text, "UTF-8") - 1
}

