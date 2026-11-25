local Transmog = _G.Transmog

-- Camera framing for the small preview tiles. Each race model carries its own camera, so a race
-- needs its own offsets; one without them starts zoomed out on the whole body. Offsets are
-- SetPosition's (depth toward the camera, sideways, height), and a positive height shows lower
-- on the body. A positive rotation turns the model's right side to the camera.

-- Where a weapon tile starts per race, before the per-weapon framing below.
local WEAPON_RACE = {
    nightelf = { 3, 0, 0 },
    gnome = { -3, 0, -0.5 },
    dwarf = { -1, 0, 0 },
    troll = { 2, 0, 0 },
    goblin = { -0.5, 0, 0 },
    scourge = { 2, 0, 0 },
}

-- An undressed model holds a one-hander in the right hand, even when it is meant for the off
-- hand; shields, off-hand-only items and bows go in the left.
local LEFT_HAND = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_RANGED = true,
}

-- Long weapons need less zoom to fit the tile.
local LONG = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_SHIELD = true,
}

-- Session-only corrections from /transmog camera, keyed by slot.
Transmog.cameraNudge = {}

function Transmog:IsWeaponSlot(slot)
    return slot == 16 or slot == 17 or slot == 18
end

-- Turns the holding hand side-on to the camera and zooms on it, as the gloves tiles do, so the
-- weapon fills the tile instead of hanging off a full-body view. zoom adds to the depth.
function Transmog:FrameWeaponModel(model, invType, zoom)
    local base = WEAPON_RACE[self.race] or { 0, 0, 0 }
    local depth, height = 4.8, 0.2
    if LONG[invType] then
        depth, height = 3.3, 0
    end
    depth = depth + (zoom or 0)

    if LEFT_HAND[invType] then
        model:SetRotation(-1.5)
        model:SetPosition(base[1] + depth, base[2] - 0.4, base[3] + height)
    else
        model:SetRotation(1.5)
        model:SetPosition(base[1] + depth, base[2] + 0.4, base[3] + height)
    end
end

function Transmog:ApplyCameraNudge(model, slot)
    local nudge = self.cameraNudge[slot]
    if not nudge then
        return
    end
    local Z, X, Y = model:GetPosition()
    model:SetPosition(Z + nudge[1], X + nudge[2], Y + nudge[3])
    if nudge[4] then
        model:SetRotation(nudge[4])
    end
end

-- A tile's model loads in the background after SetUnit/Undress/TryOn, and the client can then
-- draw it with the model's own camera (zoomed out on the whole body) or off its framing,
-- although GetPosition still reports the framing. Setting the same position again doesn't
-- fix it; dressing the tile again once the model has loaded does, as picking the slot a
-- second time does. A redressed tile can still be drawn at another zoom than its framing,
-- while moving its position by any amount puts it right. So each drawn tile is dressed again
-- early (the jump is barely seen), then moved a hair and back. The frame only runs until
-- the last step, and only touches the tiles' models.
local STEPS = {
    { 0.1, "redress" },
    { 0.2, 0.001 },
    { 0.5, -0.001 },
}

local redresser = CreateFrame("Frame")
redresser:Hide()
redresser.tiles = {}
redresser.elapsed = 0
redresser.step = 1
redresser:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    local step = STEPS[self.step]
    if self.elapsed < step[1] then
        return
    end
    for model, redress in pairs(self.tiles) do
        if model:IsVisible() then
            if step[2] == "redress" then
                redress()
            else
                local Z, X, Y = model:GetPosition()
                model:SetPosition(Z + step[2], X, Y)
            end
        end
    end
    self.step = self.step + 1
    if self.step > table.getn(STEPS) then
        self.tiles = {}
        self:Hide()
    end
end)

-- Dresses a drawn tile again (redress) once its model has had time to load.
function Transmog:RedressTileLater(model, redress)
    redresser.tiles[model] = redress
    redresser.elapsed = 0
    redresser.step = 1
    redresser:Show()
end

local function slotLabel(slot)
    return string.gsub(Transmog.inventorySlotNames[slot] or ("slot " .. slot), " Slot", "")
end

-- /transmog camera <depth> <side> <height> [rotation]: nudges the selected slot's tiles for
-- this session, to find offsets for a race or weapon type that frames badly.
function Transmog:CameraCommand(args)
    local slot = self.currentTransmogSlot
    if not TransmogFrame:IsVisible() or not slot then
        twfprint("Open the transmog window and pick a slot first, then: /transmog camera <depth> <side> <height> [rotation]")
        return
    end

    if args == "reset" then
        self.cameraNudge[slot] = nil
    elseif args ~= "" then
        local depth, side, height, rotation = string.match(args, "^(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*(%-?[%d%.]*)$")
        if not depth then
            twfprint("Usage: /transmog camera <depth> <side> <height> [rotation], or /transmog camera reset")
            return
        end
        self.cameraNudge[slot] = { tonumber(depth), tonumber(side), tonumber(height), tonumber(rotation) }
    end

    local nudge = self.cameraNudge[slot] or { 0, 0, 0 }
    twfprint(slotLabel(slot) .. " tiles, race " .. tostring(self.race) .. ": depth " .. nudge[1] .. ", side " .. nudge[2]
        .. ", height " .. nudge[3] .. (nudge[4] and (", rotation " .. nudge[4]) or "")
        .. ". Positive depth zooms in, positive height shows lower on the body.")

    if self.tab == 'illusions' then
        self:RenderIllusions()
    else
        self:RefreshItemsView()
    end
end
