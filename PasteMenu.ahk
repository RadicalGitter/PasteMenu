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
_ScriptRunnerState    := 0


; ------------------------ MODULE INCLUDES ------------------------
#Include .\includes\core_storage.ahk
#Include .\includes\script_runner.ahk
#Include .\includes\runtime_hotkeys.ahk
#Include .\includes\ui_settings.ahk
#Include .\includes\startup.ahk
#Include .\includes\core_snippets_backup.ahk
#Include .\includes\runtime_context_menu.ahk
#Include .\includes\ui_editor.ahk
#Include .\includes\paste_markup.ahk

; Drag/drop handlers for editor list controls.
OnMessage(0x0201, Editor_OnLButtonDown) ; WM_LBUTTONDOWN
OnMessage(0x0202, Editor_OnLButtonUp)   ; WM_LBUTTONUP
OnMessage(0x007B, Editor_OnContextMenu) ; WM_CONTEXTMENU
OnMessage(0x0100, Editor_OnKeyDown)     ; WM_KEYDOWN
SetTimer(UpdatePointerContext, 100)

InitOnStartup()
