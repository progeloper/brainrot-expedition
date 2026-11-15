--!nocheck
-- Failure injection covers mutation-state and deferred-fatal lifetime; existing
-- native assembly validator tests cover physical correctness independently.
return function()
	local RS=game:GetService("ReplicatedStorage")
	local Service=require(script.Parent.Parent.Services.CartAssemblyValidationService)
	local Validator=require(RS.Shared.Validation.CartAssemblyValidator)
	describe("Vehicle geometry failed-mutation rollback",function()
		it("retries only its exact failed boundary and cancels stale fatal work after restoration",function()
			local cart=Instance.new("Model");cart.Name="SPEC_GEOMETRY_FAILURE";cart.Parent=workspace
			local root=Instance.new("Part");root.Name="Root";root.Parent=cart
			local original=Validator.Validate;local failNext=false;local deferredFailures=0;local calls=0
			Validator.Validate=function(model,options)
				if model~=cart then return original(model,options)end
				calls+=1
				return {IsValid=not failNext,Warnings={},FatalErrors={},ModelName=cart.Name,CartId="SPEC",Stage=options.Stage}
			end
			local fatal=Service.FatalValidation:Connect(function(model,result,_reason,revision)
				if model~=cart then return end
				task.defer(function()if Service:IsCurrentFailure(model,result,revision)then deferredFailures+=1 end end)
			end)
			local ok,failure=xpcall(function()
				assert(Service:RegisterCart(cart))
				local begun,revision=Service:BeginMutation(cart,"geometry unit fixture");assert(begun,"Fixture mutation rejected")
				local oldSize=root.Size;root.Size=oldSize+Vector3.one
				failNext=true
				local accepted,result=Service:CompleteMutation(cart,revision,"Runtime","injected invalid unit")
				expect(accepted).to.equal(false);expect(Service:IsCurrentFailure(cart,result,revision)).to.equal(true)
				expect(Service:BeginMutation(cart,"stale rollback",revision-1)).to.equal(false)
				local retry,newRevision=Service:BeginMutation(cart,"exact geometry rollback",revision);assert(retry,"Exact failed mutation retry rejected")
				expect(Service:IsCurrentFailure(cart,result,revision)).to.equal(false)
				local beforeRestore=calls;root.Size=oldSize;root.CanCollide=false
				expect(calls).to.equal(beforeRestore)
				failNext=false;assert(Service:CompleteMutation(cart,newRevision,"Runtime","prior unit restored"))
				expect(Service:IsCartValid(cart)).to.equal(true)
				expect(Service:BeginMutation(cart,"consumed rollback",revision)).to.equal(false)
				task.wait()
				expect(deferredFailures).to.equal(0)
			end,debug.traceback)
			fatal:Disconnect();Service:ForgetCart(cart,"test cleanup");Validator.Validate=original;cart:Destroy()
			assert(ok,failure)
		end)
	end)
end
