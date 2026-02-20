-- StarterPlayer.StarterPlayerScripts.Controllers.Guis.Codes

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuiController = require(script.Parent.Parent.GuiController)
local GuiStrings = require(script.Parent.Parent:WaitForChild("GuiStrings"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RedeemCodeRemote: RemoteEvent = Remotes:WaitForChild("RedeemCode")

local Gui = GuiController.Guis.Codes
local Frame = Gui:WaitForChild("Frame")

local function findFirstByNameCI(root: Instance, name: string, className: string?): Instance?
	local target = name:lower()
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name:lower() == target then
			if className == nil or d:IsA(className) then
				return d
			end
		end
	end
	return nil
end

local ExitButton = (Frame:FindFirstChild("Exit") or findFirstByNameCI(Frame, "Exit", "GuiButton")) :: GuiButton?
local RedeemButton = (
	Frame:FindFirstChild("Redeem")
	or Frame:FindFirstChild("Confirm")
	or Frame:FindFirstChild("Use")
	or findFirstByNameCI(Frame, "Redeem", "GuiButton")
	or findFirstByNameCI(Frame, "Confirm", "GuiButton")
	or findFirstByNameCI(Frame, "Use", "GuiButton")
) :: GuiButton?
local CodeBox = (Frame:FindFirstChild("Code") or findFirstByNameCI(Frame, "Code", "TextBox")) :: TextBox?
if not CodeBox then
	CodeBox = Frame:FindFirstChildWhichIsA("TextBox", true) :: TextBox?
end

local OpenButton = GuiController.Guis.Right.Frame.Buttons:WaitForChild("Codes")

local Local = {}
local started = false

local busy = false

local originalTextColor: Color3?
local statusOkColor = Color3.fromRGB(0, 200, 0)
local statusFailColor = Color3.fromRGB(220, 0, 0)

local codeBoxHasStatus = false

local function showInBox(text: string, ok: boolean?)
	if not CodeBox or not CodeBox:IsA("TextBox") then
		return
	end
	CodeBox.Text = text
	codeBoxHasStatus = true
	if ok == true then
		CodeBox.TextColor3 = statusOkColor
	elseif ok == false then
		CodeBox.TextColor3 = statusFailColor
	elseif originalTextColor then
		CodeBox.TextColor3 = originalTextColor
	end
end

local function showStatus(key: string, ok: boolean?, ...: any)
	local text = GuiStrings.format("Codes_" .. key, key, ...)
	showInBox(text, ok)
end

local function setBusy(isBusy: boolean)
	busy = isBusy
	if RedeemButton and RedeemButton:IsA("GuiButton") then
		RedeemButton.Active = not isBusy
	end
end

function Local.Toggle()
	Gui.Enabled = not Gui.Enabled
	if Gui.Enabled then
		if CodeBox and CodeBox:IsA("TextBox") then
			CodeBox.Text = ""
			codeBoxHasStatus = false
			if originalTextColor then
				CodeBox.TextColor3 = originalTextColor
			end
			CodeBox:CaptureFocus()
		end
	end
end

function Local.Redeem()
	if busy then
		return
	end

	if not CodeBox or not CodeBox:IsA("TextBox") then
		warn("[Codes GUI] Missing TextBox (expected a TextBox named 'Code' somewhere under Frame)")
		return
	end
	local code = CodeBox.Text
	code = code:gsub("^%s+", ""):gsub("%s+$", "")
	if code == "" then
		showStatus("CodeInvalid", false)
		return
	end
	setBusy(true)
	showStatus("Checking", nil)
	print("[Codes GUI] Redeem clicked:", code)
	RedeemCodeRemote:FireServer(code)
end

function Local.Bind()
	OpenButton.MouseButton1Click:Connect(Local.Toggle)
	if ExitButton and ExitButton:IsA("GuiButton") then
		ExitButton.MouseButton1Click:Connect(Local.Toggle)
	else
		warn("[Codes GUI] Exit button not found (optional)")
	end
	if RedeemButton and RedeemButton:IsA("GuiButton") then
		-- Bind only ONE event to avoid double-fire on mouse
		if RedeemButton.Activated then
			RedeemButton.Activated:Connect(Local.Redeem)
		else
			RedeemButton.MouseButton1Click:Connect(Local.Redeem)
		end
	else
		warn("[Codes GUI] Redeem button not found (expected GuiButton named 'Redeem' or 'Confirm' under Frame)")
	end

	RedeemCodeRemote.OnClientEvent:Connect(function(ok: boolean, message: string, amount: number?)
		setBusy(false)
		if ok then
			if typeof(amount) == "number" then
				showStatus("CodeRedeemedWithAmountFormat", true, tostring(amount))
			else
				showStatus("CodeRedeemed", true)
			end
		else
			local key = if type(message) == "string" and message ~= "" then message else "CodeInvalid"
			-- Server sends message keys (e.g. CodeInvalid). Fallback to raw message if no StringValue exists.
			local localized = GuiStrings.get("Codes_" .. key, "")
			if localized ~= "" and localized ~= ("Codes_" .. key) then
				showInBox(localized, false)
			else
				showInBox(key, false)
			end
		end
	end)
end

function Local.OnStart()
	if started then
		return
	end
	started = true

	-- default: keep closed
	Gui.Enabled = false

	if CodeBox and CodeBox:IsA("TextBox") then
		originalTextColor = CodeBox.TextColor3
		CodeBox.Focused:Connect(function()
			if originalTextColor then
				CodeBox.TextColor3 = originalTextColor
			end
			-- If box currently contains a status message, clear it for typing.
			if codeBoxHasStatus then
				CodeBox.Text = ""
				codeBoxHasStatus = false
			end
		end)
	end

	if not RedeemButton or not CodeBox then
		warn("[Codes GUI] Missing controls. Dumping available UI under Codes.Frame...")
		for _, d in ipairs(Frame:GetDescendants()) do
			if d:IsA("GuiButton") then
				print("[Codes GUI] GuiButton:", d.Name, d.ClassName, d:GetFullName())
			elseif d:IsA("TextBox") then
				print("[Codes GUI] TextBox:", d.Name, d.ClassName, d:GetFullName())
			elseif d:IsA("TextLabel") then
				if d.Name:lower() == "status" then
					print("[Codes GUI] Status label candidate:", d.Name, d:GetFullName())
				end
			end
		end
		if not RedeemButton then
			warn("[Codes GUI] Redeem button not found. Expected name: Redeem/Confirm/Use")
		end
		if not CodeBox then
			warn("[Codes GUI] Code TextBox not found. Expected name: Code")
		end
	end

	Local.Bind()
end

Local.OnStart()

return {}
