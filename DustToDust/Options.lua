-- Options > AddOns > DustToDust. Every change values everything again.
local _, ns = ...

local function percent(value)
    return value .. "%"
end

function ns.registerSettings()
    local db = ns.db
    local category = Settings.RegisterVerticalLayoutCategory("DustToDust")
    ns.settingsCategory = category

    local function slider(key, name, default, min, max, step, format, tooltip)
        local variable = "DUSTTODUST_" .. key:upper()
        local setting = Settings.RegisterAddOnSetting(
            category,
            variable,
            key,
            db,
            Settings.VarType.Number,
            name,
            default
        )
        local options = Settings.CreateSliderOptions(min, max, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
        Settings.CreateSlider(category, setting, options, tooltip)
        Settings.SetOnValueChangedCallback(variable, ns.changed)
    end

    slider(
        "cut",
        "Auction house cut",
        5,
        0,
        15,
        1,
        percent,
        "What the auction house keeps of a sale. Used to value materials you'd sell."
    )

    local duration = Settings.RegisterAddOnSetting(
        category,
        "DUSTTODUST_DURATION",
        "duration",
        db,
        Settings.VarType.Number,
        "Deposit for listing",
        3
    )
    Settings.CreateDropdown(category, duration, function()
        local c = Settings.CreateControlTextContainer()
        c:Add(1, "2 hours")
        c:Add(2, "8 hours")
        c:Add(3, "24 hours")
        return c:GetData()
    end, "The listing time the deposit is counted for when valuing materials you'd sell.")
    Settings.SetOnValueChangedCallback("DUSTTODUST_DURATION", ns.changed)

    local useMyself = Settings.RegisterAddOnSetting(
        category,
        "DUSTTODUST_USE_MYSELF",
        "useMyself",
        db,
        Settings.VarType.Boolean,
        "I use the materials myself",
        false
    )
    Settings.CreateCheckbox(
        category,
        useMyself,
        "On: materials are worth their market price (for leveling Enchanting). "
            .. "Off: what selling them brings, after undercutting by a copper, the cut and the deposit."
    )
    Settings.SetOnValueChangedCallback("DUSTTODUST_USE_MYSELF", ns.changed)
    ns.useMyselfSetting = useMyself -- the panel's "I use the mats" checkbox sets it too

    slider("minProfit", "Deal: profit at least", 1, 0, 100, 1, function(v)
        return v .. "s"
    end, '"Only deals" hides anything earning less (in silver).')
    slider(
        "minMargin",
        "Deal: profit at least (of the price)",
        10,
        0,
        100,
        5,
        percent,
        '"Only deals" hides anything earning less than this share of what it costs.'
    )
    slider(
        "maxLoss",
        "Deal: chance of a loss at most",
        50,
        0,
        100,
        5,
        percent,
        '"Only deals" hides items more likely than this to disenchant into less than they cost.'
    )

    Settings.RegisterAddOnCategory(category)
end
