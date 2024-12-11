if SERVER then return end
local PANEL = {}

AccessorFunc(PANEL, "ColorPicker", "ColorPicker")

local function render_gradient(tab)
	local last_c
	local last_pos = 0

	for _, k in SortedPairsByMemberValue(tab, "Pos") do
		local pos, col = k.Pos, k.Color
		if not last_c or last_c == col then
			surface.SetDrawColor(col)
			surface.DrawRect(last_pos, 0, pos - last_pos, 16)
			last_pos = pos
		else
			for i = 0, pos - last_pos, 1 do
				local frac = i / (pos - last_pos)
				local ncol = Color(col.r * frac + last_c.r * (1 - frac), col.g * frac + last_c.g * (1 - frac), col.b * frac + last_c.b * (1 - frac))
				surface.SetDrawColor(ncol)
				surface.DrawRect(last_pos + i, 0, 1, 16)
			end
		end

		last_c = col
		last_pos = pos
	end

	surface.SetDrawColor(last_c)
	surface.DrawRect(last_pos, 0, 256 - last_pos + 1, 16)
end

local function get_color(x, tab)
	x = x * 255
	local last_c
	local last_p = 0

	for _, k in SortedPairsByMemberValue(tab, "Pos") do
		local col, pos = k.Color, k.Pos
		if x > pos then
			last_c, last_p = col, pos
			continue
		end

		if not last_c or last_c == col then
			return col
		else
			x = (x - last_p) / (pos - last_p)
			return Color(col.r * x + last_c.r * (1 - x), col.g * x + last_c.g * (1 - x), col.b * x + last_c.b * (1 - x))
		end
	end
	return last_c
end

local function get_rt(name)
	return GetRenderTargetEx(
		name,
		256, 16,
		RT_SIZE_NO_CHANGE,
		MATERIAL_RT_DEPTH_SEPARATE,
		bit.bor(4, 8),
		0,
		IMAGE_FORMAT_BGRA8888
	)
end

local tex
local function update_rt(grad)
	if not tex then tex = get_rt"lightwarp_slider" end
	render.PushRenderTarget(tex)
	cam.Start2D()
	if table.Count(grad) ~= 0 then
		render_gradient(grad)
	end
	cam.End2D()
	render.PopRenderTarget()
end



AccessorFunc( PANEL, "Dragging", "Dragging" )
AccessorFunc( PANEL, "HideKnobs", "HideKnobs" )

function PANEL:Init()
	test = self
	self.Knobs = {}
	self:SetMouseInputEnabled( true )
	self:AddKnob()
end

function PANEL:Think()
	if self.NextThink and self.NextThink > CurTime() or self:GetDragging() then return end
	self.NextThink = CurTime() + 0.3
	if GetConVarString("lightwarp_grad") ~= self:GetString() then self:SetString(GetConVarString("lightwarp_grad")) end
end

function PANEL:AddKnob(color, pos)
	if table.Count(self.Knobs) >= 12 then return end
	local knob = vgui.Create( "DButton", self )
	table.insert(self.Knobs, knob)
	knob:SetText( "" )
	knob:SetSize( 18, 18 )
	knob:NoClipping( true )
	knob.Color = color or Color(255, 0, 0)
	knob.RPos = pos or 0.5
	knob.Pos = math.Round(knob.RPos * 255)

	knob.Paint = function(panel, w, h)
		if self:GetHideKnobs() then return end
		local dep = panel.Depressed
		if self.Selected == panel then
			panel.Depressed = true
		end
		derma.SkinHook("Paint", "SliderKnob", panel, w, h)
		draw.RoundedBox(0, 7, 4, 5, 5, panel.Color)
		panel.Depressed = dep
	end

	knob.OnCursorMoved = function(panel, x, y)
		x, y = panel:LocalToScreen(x, y)
		x, y = self:ScreenToLocal(x, y)
		self:OnCursorMoved(x, y)
	end

	knob.OnMousePressed = function(panel, mcode)
		if mcode == MOUSE_RIGHT then
			panel:Remove()
			table.RemoveByValue(self.Knobs, panel)
			self:UpdateRT()
			self:OnValueChanged()
			return
		elseif mcode ~= MOUSE_MIDDLE then
			self.Selected = panel
			DButton.OnMousePressed( panel, mcode )
			self.ColorPicker:SetColor(panel.Color)
		end
	end

	knob.OnMouseReleased = function(panel, mcode)
		DButton.OnMouseReleased( panel, mcode )
		self:OnMouseReleased(mcode)
	end

	knob:SetPos(knob.RPos * self:GetWide(), self:GetTall() * 0.5)
	self:UpdateRT()

	return knob
end

function PANEL:SetCurrKnobColor(color)
	if not IsValid(self.Selected) then return end
	self.Selected.Color = color

	self:UpdateRT()
	self:OnValueChanged()
end

function PANEL:GetString()
	if self.CSTR then return self.CSTR end
	local str = ""
	local first = true
	for k, v in pairs(self.Knobs) do
		if not first then
			str = str .. ":"
		end
		str = str .. bit.tohex(v.Pos, 2) .. bit.tohex(v.Color.r, 2) .. bit.tohex(v.Color.g, 2) .. bit.tohex(v.Color.b, 2)
		first = false
	end
	self.CSTR = str
	return str
end

function PANEL:ClearKnobs()
	for k, v in pairs(self.Knobs) do
		v:Remove()
	end
	self.Knobs = {}
	self.CSTR = nil
end

function PANEL:SetString(str)
	self:ClearKnobs()
	for k, v in pairs(string.Explode(":", str)) do
		c = tonumber(v, 16)
		if not c then continue end
		p = bit.band(bit.rshift(c, 24), 0xFF)
		c = Color(bit.band(bit.rshift(c, 16), 0xFF), bit.band(bit.rshift(c, 8), 0xFF), bit.band(c, 0xFF))
		self:AddKnob(c, p / 255)
	end
end

function PANEL:OnCursorMoved( x, y, ovrr )

	if not IsValid(self.Selected) or not ovrr and (not self.Dragging and not self.Selected.Depressed) then return end

	local w = self:GetSize()
	local iw = self.Selected:GetSize()

	w = w - iw
	x = x - iw * 0.5

	x = math.Clamp( x, 0, w ) / w

	self.Selected.RPos = x
	self.Selected.Pos = math.Round(x * 255)

	self:InvalidateLayout()
	self:UpdateRT()

end

function PANEL:OnMousePressed( mcode )
	if mcode == MOUSE_LEFT then
		self.Selected = self:AddKnob(self.ColorPicker:GetColor(), self:LocalCursorPos() / self:GetWide())
		self:OnValueChanged()
	elseif mcode == MOUSE_MIDDLE then
		if table.Count(self.Knobs) < 1 then return end
		local col = get_color(self:LocalCursorPos() / self:GetWide(), self.Knobs)
		self.ColorPicker:SetColor(col)
		chat.AddText(col, "Color(" .. math.Round(col.r) .. ", " .. math.Round(col.g) .. ", " .. math.Round(col.b) .. ") #" .. bit.tohex(col.r, 2) .. bit.tohex(col.g, 2) .. bit.tohex(col.b, 2))
	else
		self.Selected = nil
	end
end

function PANEL:OnMouseReleased( mcode )
	self:SetDragging( false )
	self:MouseCapture( false )
	self:OnValueChanged()
end

function PANEL:PerformLayout()

	for k, v in pairs(self.Knobs) do
		local w, h = self:GetSize()
		local iw, ih = v:GetSize()

		v:SetPos(( v.RPos or 0 ) * w - iw * 0.5, 0.5 * h - ih * 0.5 )
	end

end

function PANEL:UpdateRT()
	self.CSTR = nil
	update_rt(self.Knobs)
	self.NextThink = CurTime() + 0.3
end

function PANEL:GetDragging()
	return self.Dragging or IsValid(self.Selected) and self.Selected.Depressed
end

function PANEL:OnValueChanged()

end

local mat
function PANEL:Paint(w, h)
	if not tex then return end
	if not mat then
		mat = CreateMaterial( "lightwarp_slider", "UnlitGeneric", {
			["$basetexture"] = tex:GetName()
		} );
	end
	surface.SetDrawColor(255, 255, 255)
	surface.SetMaterial(mat)
	surface.DrawTexturedRect(0, 0, w, h)
end


vgui.Register("lightwarp_slider", PANEL, "Panel")
