AddCSLuaFile("lightwarp/lightwarp_slider.lua")
include("lightwarp/lightwarp_slider.lua")

local slider

TOOL.Category = "Render"
TOOL.Name = "Lightwarp Editor"

TOOL.ClientConVar["grad"] = "4b383838:afc9c7c7"

TOOL.Information = {
	{ name = "left", stage = 0},
	{ name = "right" },
	{ name = "reload" },
}

local function get_rt(name)
	return GetRenderTargetEx(
		name,
		256, 16,
		RT_SIZE_NO_CHANGE,
		MATERIAL_RT_DEPTH_NONE,
		bit.bor(4, 8),
		0,
		IMAGE_FORMAT_BGRA8888
	)
end

local mats = {}

function create_materials(ent, lw)
	for k, v in pairs(ent:GetMaterials()) do
		if v:find("eyeball") or v:find("lens") then continue end

		local name
		local mat = ent:GetSubMaterial(k - 1)
		local ovt
		if mat ~= "" and mat ~= nil then
			if mat:StartsWith("!lw") then
				v = mat:sub(string.find(mat, "_", 1, true) + 1, mat:len())
				name = "lw" .. ent:EntIndex() .. "_" .. v
				ovt = true
			else
				name = "lw" .. ent:EntIndex() .. "_" .. mat
				v = mat
			end
		else
			name = "lw" .. ent:EntIndex() .. "_" .. v
		end

		if not mats[name] then
			local tmat = Material(v)
			local tab = tmat:GetKeyValues()
			tab["$lightwarptexture"] = lw:GetName()
			local flags = tab["$flags"]
			local flags2 = tab["$flags2"]
			tab["$flags"] = nil
			tab["$flags2"] = nil
			tab["$flags_defined2"] = nil
			tab["$flags_defined"] = nil
			tab["$bumpmap"] = tmat:GetString("$bumpmap")
			tab["$basetexture"] = tmat:GetString("$basetexture")
			tab["$detail"] = tmat:GetString("$detail")
			tab["$phongwarptexture"] = tmat:GetString("$phongwarptexture")
			mats[name] = CreateMaterial(name, "VertexLitGeneric", tab)
			mats[name]:SetInt("$flags", flags)
			mats[name]:SetInt("$flags2", flags2)
		end
		if ovt then ent:SetSubMaterial(k - 1, "!" .. name) end
	end
end

local function set_materials(ent, lw)
	for k, v in pairs(ent:GetMaterials()) do
		local mat = ent:GetSubMaterial(k - 1):sub(2, -1)
		if not mats[mat] then continue end
		mats[mat]:SetTexture("$lightwarptexture", lw)
	end
end

function TOOL:LeftClick(tr)
	if not IsValid(tr.Entity) then
		if SERVER then self:GetOwner():ConCommand("_lwed -1") end
		return true
	end

	if SERVER then
		local ent = tr.Entity
		if IsValid(ent.AttachedEntity) then ent = ent.AttachedEntity end

		self:GetOwner():ConCommand("_lwed " .. ent:EntIndex())
		local lw = self:GetClientInfo("grad")
		ent:SetNWString("CLightwarp", lw)

		for k, v in pairs(ent:GetMaterials()) do
			if v:find("eyeball") or v:find("lens") then continue end
			local name
			local mat = ent:GetSubMaterial(k - 1)
			if mat ~= "" then
				if mat:StartsWith("!lw") then
					name = mat
				else
					name = "!lw" .. ent:EntIndex() .. "_" .. ent:GetSubMaterial(k-1)
				end
			else
				name = "!lw" .. ent:EntIndex() .. "_" .. v
			end
			ent:SetSubMaterial(k - 1, name)
		end

		duplicator.StoreEntityModifier(ent, "tlightwarp_editor", {lw})
	end
	return true
end

function TOOL:RightClick(tr)
	if not IsValid(tr.Entity) then return false end

	local ent = tr.Entity
	if IsValid(ent.AttachedEntity) then ent = ent.AttachedEntity end

	local lw = ent:GetNWString("CLightwarp", "")
	if not lw or lw == "" or lw == "-1" then return false end

	if CLIENT then
		RunConsoleCommand("lightwarp_grad", lw)
		if IsValid(slider) then slider:SetString(lw) end
	elseif SERVER and game.SinglePlayer() then
		self:GetOwner():ConCommand("lightwarp_grad " .. lw)
	end
	return true
end

function TOOL:Reload(tr)
	if not IsValid(tr.Entity) then return false end

	local ent = tr.Entity
	if IsValid(ent.AttachedEntity) then ent = ent.AttachedEntity end

	if SERVER then
		timer.Simple(0.1, function() self:GetOwner():ConCommand("_lwed -1") end)
		ent:SetNWString("CLightwarp", "-1")
		for k, v in pairs(ent:GetMaterials()) do
			if v:find("eyeball") or v:find("lens") then continue end
			ent:SetSubMaterial(k - 1, "")
		end

		duplicator.ClearEntityModifier(ent, "tlightwarp_editor")
	end
	return true
end

local hide_halo
if CLIENT then
	hide_halo = CreateClientConVar("lightwarp_hidehalo", "0", true)
	language.Add("lw.balloon", "Balloon")
	language.Add("lw.pyro", "TF2 Shading")
	language.Add("lw.blorange", "Blorange")
	language.Add("lw.cel", "Toon Shading")
	language.Add("tool.lightwarp.left", "Apply Custom Lightwarp / Select Entity")
	language.Add("tool.lightwarp.right", "Copy Custom Lightwarp")
	language.Add("tool.lightwarp.reload", "Remove Custom Lightwarp")
	language.Add("tool.lightwarp.name", "Lightwarp Editor")
	language.Add("tool.lightwarp.desc", "Allows you to edit the Lightwarp Texture of any $phong enabled model")

	local ConVarsDefault = TOOL:BuildConVarList()

	if table.Count(presets.GetTable("lightwarp")) < 1 then
		presets.Add("lightwarp", "Default", ConVarsDefault)
		presets.Add("lightwarp", "TF2 Warp", {["lightwarp_grad"] = "0112091a:bbbbbbbb:71685457:331e1229:6124192e:80af8389:a1c7a6ab:ffeaeaeaz"})
		presets.Add("lightwarp", "Toon Warp", {["lightwarp_grad"] = "28000000:d2ffffff:2b464646:5e464646:62858585:92858585:9bd3d3d3:ced3d3d3"})
	end

	function TOOL.BuildCPanel(pnl)
		pnl:Help("Sets the lightwarp texture for a model's material (Will modify all submaterials)")

		local pre = pnl:AddControl( "ComboBox", { MenuButton = 1, Folder = "lightwarp", Options = {},
			CVars = table.GetKeys( ConVarsDefault ) } )

		function pre:OnSelect(index, value, data)
			for k, v in pairs( data ) do
				RunConsoleCommand( k, v )
				if k == "lightwarp_grad" then
					slider:SetString(v)
				end
			end
		end

		local color = vgui.Create( "DColorMixer", pnl)
		color:SetColor(Color( 255, 255, 255 ))
		color:SetPalette(true)
		color:SetAlphaBar(false)
		color:SetWangs(true)
		color:SetColor(Color(152,157,161))
		pnl:AddItem(color)

		local hide = pnl:CheckBox("Hide Control Points")
		function hide:OnChange(data)
			slider:SetHideKnobs(data)
		end

		pnl:CheckBox("Hide Selection Halo", "lightwarp_hidehalo")

		slider = vgui.Create("lightwarp_slider", pnl)
		slider:SetColorPicker(color)
		slider:SetString(GetConVarString("lightwarp_grad"))
		pnl:AddItem(slider)

		function color:ValueChanged(col)
			slider:SetCurrKnobColor(col)
		end

		function slider:OnValueChanged()
			RunConsoleCommand("lightwarp_grad", slider:GetString())
		end

		local hlp = pnl:ControlHelp("Right click to remove Control Points. Middle click to get cursor's Color")
		hlp:DockMargin(13, 5, 0, 5)
		hlp:SetColor(Color(0, 112, 216))

		local abt = vgui.Create("DForm", pnl)
		abt:SetLabel("Info")
		pnl:AddItem(abt)
		abt:Help("Made by Eskil")

		local btn = abt:Button("Workshop Page")
		btn.DoClick = function() gui.OpenURL("https://steamcommunity.com/sharedfiles/filedetails/?id=3369379315") end

		local capture = abt:Button("Export Lightwarp to PNG file")
		capture.DoClick = function()
			Derma_StringRequest("Export Lightwarp", "Enter filename (Saved in garrysmod/data/lightwarps/*.png)", "", function(str)
				str = str:Replace(" ", "_"):StripExtension()
				render.PushRenderTarget(get_rt"lightwarp_slider")
				local data = render.Capture({
					format = "png",
					x = 0,
					y = 0,
					w = 256,
					h = 16,
					alpha = false,
				})
				file.CreateDir("lightwarps")
				file.Write("lightwarps/" .. str .. ".png", data)
				render.PopRenderTarget()
				timer.Simple(0.1, function() slider:UpdateRT() end)
				chat.AddText(color_white, "Exported to garrysmod/data/lightwarps/" .. str .. ".png")
			end, nil, "Export")
		end

		pnl:InvalidateLayout()
	end
end

local function str_to_tbl(str)
	local tab = {}
	for k, v in pairs(string.Explode(":", str)) do
		c = tonumber(v, 16)
		if not c then continue end
		p = bit.band(bit.rshift(c, 24), 0xFF)
		c = Color(bit.band(bit.rshift(c, 16), 0xFF), bit.band(bit.rshift(c, 8), 0xFF), bit.band(c, 0xFF))
		tab[p] = c
	end
	return tab
end

local function render_gradient(tab)
	local last_c
	local last_pos = 0

	for pos, col in SortedPairs(tab) do
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

if CLIENT then
	local cv = CreateClientConVar("_lwed", "-1", false, false)
	local gv
	hook.Add("OnEntityCreated", "Lightwarp_Proxy", function(nent)
		nent:SetNWVarProxy("CLightwarp", function(ent, _, old, new)
			timer.Simple(0.1, function()
				new = ent:GetNWString("CLightwarp")
				if (new == "" or new == "-1") and ent.LWarp then
					ent.LWarp = nil
					return
				end
				if ent.LWarp == new then return end
				ent.LWarp = new

				local lw = get_rt("lightwarp_" .. ent:EntIndex())
				local grad = str_to_tbl(new)

				render.PushRenderTarget(lw)
				cam.Start2D()
					render_gradient(grad)
				cam.End2D()
				render.PopRenderTarget()

				create_materials(ent, lw)
			end)
		end)
	end)

	cvars.RemoveChangeCallback("_lwed", "lw")
	cvars.AddChangeCallback("_lwed", function(_, old, new)
		timer.Simple(0.7, function()
			local eold = Entity(old)
			local enew = Entity(new)
			if IsValid(eold) and eold ~= enew then
				local lw = get_rt("lightwarp_" .. old)
				set_materials(eold, lw)
			end
			if new ~= -1 and IsValid(enew) then
				local lw = get_rt"lightwarp_slider"
				set_materials(enew, lw)
			end
		end, "lw")
	end)

	local red = Color(255, 0, 0)
	hook.Add("PreDrawHalos", "Lightwarp_Halo", function()
		local int = cv:GetInt()
		local wep = LocalPlayer():GetActiveWeapon()
		if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" or hide_halo:GetBool() or int == -1 then return end

		local ent = Entity(cv:GetInt())
		gv = gv or GetConVar("lightwarp_grad")

		if not IsValid(ent) then RunConsoleCommand("_lwed", -1) return end
		halo.Add({ent}, gv:GetString() == ent:GetNWString("CLightwarp") and color_white or red, 5, 5, 2)
	end)
else
	duplicator.RegisterEntityModifier("tlightwarp_editor", function(ply, ent, data)
		ent:SetNWString("CLightwarp", data[1])
		for k, v in pairs(ent:GetMaterials()) do
			if v:find("eyeball") or v:find("lens") then continue end

			local mat = ent:GetSubMaterial(k - 1)
			if mat:StartsWith("!lw") then
				v = mat:sub(string.find(mat, "_", 1, true) + 1, mat:len())
				ent:SetSubMaterial(k - 1, "!lw" .. ent:EntIndex() .. "_" .. v)
			end
		end
	end)

	-- Fix Adv Bonemerge
	local oldbm
	timer.Simple(5, function()
		oldbm = oldbm or CreateAdvBonemergeEntity
		if not oldbm then return end
		function CreateAdvBonemergeEntity(target, parent, ply, alwaysreplace, keepparentempty, matchnames, x, y)
			if not IsValid(target) then return end
			local emats = {}
			for k, v in pairs(target:GetMaterials()) do
				emats[k - 1] = target:GetSubMaterial(k - 1)
			end

			local ent = oldbm(target, parent, ply, alwaysreplace, keepparentempty, matchnames, x, y)
			if not IsValid(ent) then return end
			for k, v in pairs(emats) do
				ent:SetSubMaterial(k, v)
			end
			return ent
		end
	end)
end