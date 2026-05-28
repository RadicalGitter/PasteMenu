; ---------------------------------------------------------------------
; LLM pricing:
; - Locally cached price table fetched from LiteLLM community JSON.
; - Cached model list from Anthropic /v1/models.
; - Cost estimator used by the confirmation window.
; - Monthly staleness nag that snoozes 30 days when ignored.
; ---------------------------------------------------------------------

global _LLMPricingState := 0

; --- Defaults baked in so we have something to show before the first fetch.
; Values are in USD per 1,000,000 tokens. Will be overwritten when the user runs Update pricing.
LLMPricingBakedDefaults() {
    return Map(
        "claude-opus-4-7",            {input: 15.0, output: 75.0, cache_write: 18.75, cache_read: 1.50},
        "claude-sonnet-4-6",          {input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30},
        "claude-sonnet-4-20250514",   {input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30},
        "claude-haiku-4-5-20251001",  {input:  1.0, output:  5.0, cache_write:  1.25, cache_read: 0.10},
        "claude-3-7-sonnet-latest",   {input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30},
        "claude-3-5-sonnet-latest",   {input:  3.0, output: 15.0, cache_write:  3.75, cache_read: 0.30},
        "claude-3-5-haiku-latest",    {input:  0.8, output:  4.0, cache_write:  1.00, cache_read: 0.08},
        "claude-3-opus-latest",       {input: 15.0, output: 75.0, cache_write: 18.75, cache_read: 1.50}
    )
}

LLMPricingInit() {
    global _LLMPricingState
    if IsObject(_LLMPricingState)
        return
    _LLMPricingState := {
        prices: LLMPricingBakedDefaults(),
        models: [],
        pricingUpdated: "",
        modelsUpdated: "",
        nextNagAt: ""
    }
}

LLMPricingFilePath() {
    global DataRootDir
    return DataRootDir "\pricing.ini"
}

LLMPricingLoad() {
    global _LLMPricingState
    LLMPricingInit()
    pricingFile := LLMPricingFilePath()
    if !FileExist(pricingFile)
        return

    _LLMPricingState.pricingUpdated := Trim(IniRead(pricingFile, "meta", "pricing_updated", ""))
    _LLMPricingState.modelsUpdated := Trim(IniRead(pricingFile, "meta", "models_updated", ""))
    _LLMPricingState.nextNagAt := Trim(IniRead(pricingFile, "meta", "next_nag_at", ""))

    modelsLine := Trim(IniRead(pricingFile, "models", "list", ""))
    if (modelsLine != "") {
        list := []
        Loop Parse modelsLine, "," {
            v := Trim(A_LoopField)
            if (v != "")
                list.Push(v)
        }
        _LLMPricingState.models := list
    }

    sectionsRaw := ""
    try sectionsRaw := IniRead(pricingFile)
    if (sectionsRaw = "")
        return

    fresh := Map()
    Loop Parse sectionsRaw, "`n", "`r" {
        section := Trim(A_LoopField)
        if (section = "" || section = "meta" || section = "models")
            continue
        inputCost := Trim(IniRead(pricingFile, section, "input", ""))
        outputCost := Trim(IniRead(pricingFile, section, "output", ""))
        if (inputCost = "" && outputCost = "")
            continue
        cw := Trim(IniRead(pricingFile, section, "cache_write", ""))
        cr := Trim(IniRead(pricingFile, section, "cache_read", ""))
        fresh[section] := {
            input: (inputCost != "") ? (inputCost + 0) : 0.0,
            output: (outputCost != "") ? (outputCost + 0) : 0.0,
            cache_write: (cw != "") ? (cw + 0) : 0.0,
            cache_read: (cr != "") ? (cr + 0) : 0.0
        }
    }
    if (fresh.Count > 0)
        _LLMPricingState.prices := fresh
}

LLMPricingSave() {
    global _LLMPricingState
    LLMPricingInit()
    pricingFile := LLMPricingFilePath()
    EnsureParentDirectory(pricingFile)

    ; Wipe then rewrite to avoid leftover stale sections.
    try FileDelete(pricingFile)

    IniWrite(_LLMPricingState.pricingUpdated, pricingFile, "meta", "pricing_updated")
    IniWrite(_LLMPricingState.modelsUpdated, pricingFile, "meta", "models_updated")
    IniWrite(_LLMPricingState.nextNagAt, pricingFile, "meta", "next_nag_at")

    modelsLine := ""
    for _, id in _LLMPricingState.models {
        if (modelsLine != "")
            modelsLine .= ","
        modelsLine .= id
    }
    IniWrite(modelsLine, pricingFile, "models", "list")

    for id, p in _LLMPricingState.prices {
        IniWrite(LLMPricingFormatNumber(p.input), pricingFile, id, "input")
        IniWrite(LLMPricingFormatNumber(p.output), pricingFile, id, "output")
        IniWrite(LLMPricingFormatNumber(p.cache_write), pricingFile, id, "cache_write")
        IniWrite(LLMPricingFormatNumber(p.cache_read), pricingFile, id, "cache_read")
    }
}

LLMPricingFormatNumber(n) {
    if (n = "" || n = 0)
        return "0"
    ; Show enough precision but trim trailing zeros.
    s := Format("{:.6f}", n + 0)
    s := RegExReplace(s, "\.?0+$", "")
    if (s = "")
        s := "0"
    return s
}

LLMPricingForModel(modelId) {
    LLMPricingInit()
    global _LLMPricingState
    if (modelId = "")
        return 0
    if _LLMPricingState.prices.Has(modelId)
        return _LLMPricingState.prices[modelId]
    ; Try stripping a date suffix like -20250514.
    if RegExMatch(modelId, "^(.*)-\d{8}$", &m) {
        if _LLMPricingState.prices.Has(m[1] "-latest")
            return _LLMPricingState.prices[m[1] "-latest"]
    }
    return 0
}

LLMPricingModelList() {
    LLMPricingInit()
    global _LLMPricingState
    return _LLMPricingState.models
}

LLMPricingEstimateInputTokens(text) {
    if (text = "")
        return 0
    return Ceil(StrLen(text) / 4)
}

; Returns "" if no pricing for model; otherwise an estimate description.
LLMPricingFormatCostLine(modelId, inputTokens, outputMaxTokens) {
    p := LLMPricingForModel(modelId)
    if !IsObject(p)
        return ""
    costIn := inputTokens * p.input / 1000000.0
    costOut := outputMaxTokens * p.output / 1000000.0
    total := costIn + costOut
    return Format("~{:d} in / {:d} out max → ~${:.4f} (${:.2f} in + ${:.2f} out per Mtok)"
        , inputTokens, outputMaxTokens, total, p.input, p.output)
}

LLMPricingDaysSinceUpdate() {
    LLMPricingInit()
    global _LLMPricingState
    if (_LLMPricingState.pricingUpdated = "")
        return -1
    try {
        diffSec := DateDiff(A_Now, _LLMPricingState.pricingUpdated, "Seconds")
        return Floor(diffSec / 86400)
    }
    return -1
}

LLMPricingShouldNag() {
    LLMPricingInit()
    global _LLMPricingState
    ; Never fetched → nag.
    if (_LLMPricingState.pricingUpdated = "")
        return true
    ; Snooze window active?
    if (_LLMPricingState.nextNagAt != "") {
        try {
            if (_LLMPricingState.nextNagAt > A_Now)
                return false
        }
    }
    days := LLMPricingDaysSinceUpdate()
    return (days < 0 || days >= 30)
}

LLMPricingSnoozeNag() {
    global _LLMPricingState
    LLMPricingInit()
    try _LLMPricingState.nextNagAt := DateAdd(A_Now, 30, "Days")
    LLMPricingSave()
}

; --- Fetch -----------------------------------------------------------

LLMPricingLiteLLMUrl() {
    return "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
}

LLMPricingFetchLiteLLM(&errMsg) {
    errMsg := ""
    req := 0
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 10000, 15000, 30000)
        req.Open("GET", LLMPricingLiteLLMUrl(), false)
        req.SetRequestHeader("Accept", "application/json")
        req.Send()
    } catch as err {
        errMsg := "Network error: " err.Message
        return 0
    }
    status := 0
    try status := req.Status
    if (status < 200 || status >= 300) {
        errMsg := "HTTP " status " from LiteLLM"
        return 0
    }
    body := ""
    try body := req.ResponseText
    if (body = "") {
        errMsg := "Empty response from LiteLLM"
        return 0
    }
    parsed := LLMPricingParseLiteLLM(body)
    if (parsed.Count = 0) {
        errMsg := "Could not parse any Anthropic entries from LiteLLM."
        return 0
    }
    return parsed
}

LLMPricingFetchModels(&errMsg) {
    errMsg := ""
    apiKey := LLMCallsReadApiKey()
    if (apiKey = "") {
        errMsg := "API key not set."
        return 0
    }
    req := 0
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 10000, 15000, 30000)
        req.Open("GET", "https://api.anthropic.com/v1/models?limit=100", false)
        req.SetRequestHeader("x-api-key", apiKey)
        req.SetRequestHeader("anthropic-version", "2023-06-01")
        req.Send()
    } catch as err {
        errMsg := "Network error: " err.Message
        return 0
    }
    status := 0
    try status := req.Status
    if (status < 200 || status >= 300) {
        errMsg := "HTTP " status " from Anthropic"
        return 0
    }
    body := ""
    try body := req.ResponseText
    if (body = "") {
        errMsg := "Empty response from Anthropic"
        return 0
    }
    return LLMPricingParseModels(body)
}

LLMPricingParseModels(json) {
    out := []
    pos := 1
    pat := '"id"\s*:\s*"([^"]+)"'
    while (matchPos := RegExMatch(json, pat, &m, pos)) {
        out.Push(m[1])
        pos := matchPos + StrLen(m[0])
    }
    return out
}

; Walk LiteLLM JSON, returning Map(modelId -> {input, output, cache_write, cache_read}) for
; entries whose litellm_provider is "anthropic". Numbers are in USD per 1,000,000 tokens.
LLMPricingParseLiteLLM(text) {
    out := Map()
    len := StrLen(text)
    pos := InStr(text, "{")
    if !pos
        return out
    pos += 1

    while (pos <= len) {
        ; Find next top-level "key": {
        if !RegExMatch(text, '"([^"\\]+)"\s*:\s*\{', &m, pos)
            break
        modelId := m[1]
        openPos := m.Pos[0] + m.Len[0] - 1  ; index of "{"
        ; Walk to matching "}"
        depth := 1
        i := openPos + 1
        insideStr := false
        while (i <= len && depth > 0) {
            ch := SubStr(text, i, 1)
            if insideStr {
                if (ch = "\") {
                    i += 2
                    continue
                }
                if (ch = '"')
                    insideStr := false
                i += 1
                continue
            }
            if (ch = '"')
                insideStr := true
            else if (ch = "{")
                depth += 1
            else if (ch = "}")
                depth -= 1
            i += 1
        }
        blockEnd := i - 1
        block := SubStr(text, openPos, blockEnd - openPos + 1)

        if RegExMatch(block, '"litellm_provider"\s*:\s*"anthropic"') {
            cleanId := LLMPricingNormalizeModelId(modelId)
            if (cleanId != "") {
                entry := {input: 0.0, output: 0.0, cache_write: 0.0, cache_read: 0.0}
                if RegExMatch(block, '"input_cost_per_token"\s*:\s*([0-9.eE+-]+)', &im)
                    entry.input := (im[1] + 0) * 1000000.0
                if RegExMatch(block, '"output_cost_per_token"\s*:\s*([0-9.eE+-]+)', &om)
                    entry.output := (om[1] + 0) * 1000000.0
                if RegExMatch(block, '"cache_creation_input_token_cost"\s*:\s*([0-9.eE+-]+)', &cwm)
                    entry.cache_write := (cwm[1] + 0) * 1000000.0
                if RegExMatch(block, '"cache_read_input_token_cost"\s*:\s*([0-9.eE+-]+)', &crm)
                    entry.cache_read := (crm[1] + 0) * 1000000.0
                ; Only keep entries that have at least input or output price.
                if (entry.input > 0 || entry.output > 0)
                    out[cleanId] := entry
            }
        }

        pos := blockEnd + 1
    }
    return out
}

LLMPricingNormalizeModelId(id) {
    ; LiteLLM sometimes prefixes Anthropic IDs with "anthropic/" — strip it.
    if (SubStr(id, 1, 10) = "anthropic/")
        id := SubStr(id, 11)
    ; Skip bedrock/vertex variants which carry the prefix in the key.
    if InStr(id, "bedrock") || InStr(id, "vertex_ai")
        return ""
    return id
}

; Update prices + (best-effort) models. Returns true on success, sets errMsg otherwise.
LLMPricingUpdateAll(&errMsg) {
    errMsg := ""
    LLMPricingInit()
    global _LLMPricingState

    priceErr := ""
    prices := LLMPricingFetchLiteLLM(&priceErr)
    if !IsObject(prices) {
        errMsg := priceErr
        return false
    }

    modelsErr := ""
    models := LLMPricingFetchModels(&modelsErr)

    _LLMPricingState.prices := prices
    _LLMPricingState.pricingUpdated := A_Now
    if IsObject(models) && models.Length > 0 {
        _LLMPricingState.models := models
        _LLMPricingState.modelsUpdated := A_Now
    }
    try _LLMPricingState.nextNagAt := DateAdd(A_Now, 30, "Days")
    LLMPricingSave()

    if (modelsErr != "" && (!IsObject(models) || models.Length = 0))
        errMsg := "Pricing updated. Model list refresh failed: " modelsErr
    return true
}

LLMPricingFormatTimestamp(ts) {
    if (ts = "")
        return "never"
    try {
        days := DateDiff(A_Now, ts, "Days")
        if (days <= 0)
            return "today"
        if (days = 1)
            return "1 day ago"
        return days " days ago"
    }
    return ts
}
