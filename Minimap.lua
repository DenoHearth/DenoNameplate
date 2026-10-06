-- Minimap button: left-click opens the options, drag moves it around the minimap rim.
-- Named like a LibDBIcon button so minimap button collectors (Button Drawer) pick it up.
local ADDON, ns = ...

local button

local function Place()
	local angle = math.rad(ns.db.general.minimap.angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
	if not button then return end
	button:SetShown(ns.db.general.minimap.show)
end

function ns.CreateMinimapButton()
	button = CreateFrame("Button", "LibDBIcon10_DenoNameplate", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function()
		if ns.category then Settings.OpenToCategory(ns.category:GetID()) end
	end)

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.general.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Deno Nameplate")
		GameTooltip:AddLine("Click: options", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	Place()
	ns.UpdateMinimapButton()
end
