-- Options > AddOns > CrateExpectations. Every change redraws the marks.
local _, ns = ...

function ns.registerSettings()
    local db = ns.db
    local category = Settings.RegisterVerticalLayoutCategory("CrateExpectations")
    ns.settingsCategory = category

    local function register(key, varType, name, default)
        local variable = "CRATEEXPECTATIONS_" .. key:upper()
        local setting =
            Settings.RegisterAddOnSetting(category, variable, key, db, varType, name, default)
        Settings.SetOnValueChangedCallback(variable, ns.refresh)
        return setting
    end

    Settings.CreateCheckbox(
        category,
        register("marks", Settings.VarType.Boolean, "Crate on item icons", true),
        "A small crate on every item a Waylaid Crate takes: bags, bank, merchant, loot, mail, "
            .. "trade, guild bank and auction house."
    )

    Settings.CreateDropdown(
        category,
        register("corner", Settings.VarType.String, "Corner", "BOTTOMLEFT"),
        function()
            local c = Settings.CreateControlTextContainer()
            c:Add("TOPLEFT", "Top left")
            c:Add("TOPRIGHT", "Top right")
            c:Add("BOTTOMLEFT", "Bottom left")
            c:Add("BOTTOMRIGHT", "Bottom right")
            return c:GetData()
        end,
        "Where the crate sits. Taken already: top left (junk coin, upgrade arrows), "
            .. "bottom right (stack count), top right (Polestar's quest items)."
    )

    local options = Settings.CreateSliderOptions(20, 70, 5)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
        return v .. "%"
    end)
    Settings.CreateSlider(
        category,
        register("size", Settings.VarType.Number, "Size", 40),
        options,
        "The crate's size, as a share of the item icon's width."
    )

    Settings.CreateCheckbox(
        category,
        register("tooltip", Settings.VarType.Boolean, "Tooltip line", true),
        'Adds "Waylaid Crate: <shipment> (<count>)" to the tooltip of items the crates take.'
    )

    Settings.RegisterAddOnCategory(category)
end
