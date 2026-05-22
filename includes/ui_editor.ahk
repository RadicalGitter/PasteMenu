; ---------------------------------------------------------------------
; Editor module:
; - Quick entry dialog
; - Category/entry editor
; - Drag/drop reorder and move between categories
; ---------------------------------------------------------------------

; Opens the compact quick-entry dialog for a specific category.
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

    ; Skip per-entry metadata backup for rename-overwrite collisions because
    ; two logical changes happen at once (rename + overwrite existing target).
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

    ; Persist resulting reorder/move and refresh editor in-place.
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
