--!nocheck
local LocalCart = require(script.Parent.Parent.State.LocalCartState)
local Hud = require(script.Parent.ExactHudController)
local Controller = {}
local connections = {}
local stateConnection
local cart
local function update()
	Hud.Cargo(cart, cart and cart:GetAttribute("CargoCount"), cart and cart:GetAttribute("CargoCapacity"))
end
local function bind(nextCart)
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	cart = nextCart
	if cart then
		for _, a in { "CargoCount", "CargoCapacity" } do
			table.insert(connections, cart:GetAttributeChangedSignal(a):Connect(update))
		end
		table.insert(
			connections,
			cart.Destroying:Connect(function()
				bind(nil)
			end)
		)
	end
	update()
end
function Controller.Start()
	if stateConnection then
		return
	end
	Hud.Start()
	bind(LocalCart.GetCart())
	stateConnection = LocalCart.Changed:Connect(bind)
end
function Controller.ShowCargoFullFeedback()
	Hud.Feedback("Cart full", "cargo-full:" .. tostring(cart and cart:GetAttribute("CargoRevision")))
end
function Controller.Stop()
	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end
	bind(nil)
end
return Controller
