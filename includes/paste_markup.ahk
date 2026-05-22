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

