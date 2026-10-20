local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
local gameplayRemotes = remotes and remotes:WaitForChild("Gameplay", 5)

local MAX_DIST = 1000
local TARGET_SPEED = 23
local RESET_DELAY = 5.0
local ROUND_START_DELAY = 1.5
local WEBHOOK_INTERVAL = 1800

local enabled = false
local afkActive = false
local isLoaded = false
local bagIsFull = false
local isWaitingForCoins = false
local activeCoins = {}
local blacklistedCoins = {}
local currentTarget = nil
local noCoinsStartTime = nil
local hasCollectedThisLife = false

local linearVelocity = nil
local velocityAttachment = nil
local noclipConnection = nil
local heartbeatConnection = nil
local coinAddedConnection = nil
local coinRemovedConnection = nil
local coinsStartedConnection = nil
local coinCollectedConnection = nil
local targetFinderThread = nil
local characterAddedConnection = nil

local characterParts = {}

local flingBagFullEnabled = false
local flingAfterDeathEnabled = false
local flingActive = false
local flingOldPos = nil
local flingFPDH = workspace.FallenPartsDestroyHeight

local PlayerData = nil
local PlayerDataChanged = nil
local RolesPlrName = { ["Sheriff"] = false, ["Murderer"] = false, ["Innocent"] = false, ["Hero"] = false }

local webhookUrl = ""
local sessionStartTime = os.time()
local coinsCollectedTotal = 0
local flingsTotal = 0
local resetsTotal = 0
local lastWebhookTime = os.time()
local webhookThread = nil

local function findRemote(name)
    local ok, result = pcall(function()
        return ReplicatedStorage:FindFirstChild(name, true)
    end)
    if ok and result then return result end
    return nil
end

PlayerData = findRemote("GetPlayerData")
PlayerDataChanged = findRemote("PlayerDataChanged")

local function refreshRoles()
    if not PlayerData then return end
    local ok, data = pcall(function() return PlayerData:InvokeServer() end)
    if not ok or not data then return end
    for name, info in pairs(data) do
        local plr = Players:FindFirstChild(name)
        if plr and info and info.Role then
            RolesPlrName[info.Role] = plr
        end
    end
end

if PlayerDataChanged then
    PlayerDataChanged.OnClientEvent:Connect(function(data)
        for name, info in pairs(data) do
            local plr = Players:FindFirstChild(name)
            if plr and info and info.Role then
                RolesPlrName[info.Role] = plr
            end
        end
    end)
end

task.spawn(function()
    task.wait(1)
    refreshRoles()
end)

local function findMurdererByKnife()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local char = plr.Character
            local bp = plr:FindFirstChild("Backpack")
            local hasKnife = char:FindFirstChild("Knife") or (bp and bp:FindFirstChild("Knife"))
            if hasKnife and char:FindFirstChild("HumanoidRootPart") then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    return plr
                end
            end
        end
    end
    return nil
end

local function findMurderer()
    local m = RolesPlrName["Murderer"]
    if m and m.Character and m.Character:FindFirstChild("HumanoidRootPart") then
        return m
    end
    refreshRoles()
    m = RolesPlrName["Murderer"]
    if m and m.Character and m.Character:FindFirstChild("HumanoidRootPart") then
        return m
    end
    return findMurdererByKnife()
end

local function SkidFling(target)
    local myChar = player.Character
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local myRoot, tChar = myHum and myHum.RootPart, target.Character
    if not tChar then return end

    local tHum, tRoot, tHead, tAcc, tHandle
    if tChar:FindFirstChildOfClass("Humanoid") then tHum = tChar:FindFirstChildOfClass("Humanoid") end
    if tHum and tHum.RootPart then tRoot = tHum.RootPart end
    if tChar:FindFirstChild("Head") then tHead = tChar.Head end
    if tChar:FindFirstChildOfClass("Accessory") then tAcc = tChar:FindFirstChildOfClass("Accessory") end
    if tAcc and tAcc:FindFirstChild("Handle") then tHandle = tAcc.Handle end

    if not (myChar and myHum and myRoot) then return end
    if tHum and tHum.Sit then return end

    if myRoot.Velocity.Magnitude < 50 then
        flingOldPos = myRoot.CFrame
    end

    if tHead then
        workspace.CurrentCamera.CameraSubject = tHead
    elseif tHandle then
        workspace.CurrentCamera.CameraSubject = tHandle
    elseif tHum and tRoot then
        workspace.CurrentCamera.CameraSubject = tHum
    end

    if not tChar:FindFirstChildWhichIsA("BasePart") then return end

    local function setCF(pos, ang, vel)
        myRoot.CFrame = CFrame.new(pos.Position) * ang * vel
        myChar:SetPrimaryPartCFrame(CFrame.new(pos.Position) * ang * vel)
        myRoot.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
        myRoot.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
    end

    local function flingLoop(tPart)
        local dur, startT, rot = 2, tick(), 0
        repeat
            if myRoot and tHum then
                if tPart.Velocity.Magnitude < 50 then
                    rot = rot + 100
                    setCF(tPart, CFrame.new(0, 1.5, 0) + tHum.MoveDirection * tPart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(rot), 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, -1.5, 0) + tHum.MoveDirection * tPart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(rot), 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, 1.5, 0) + tHum.MoveDirection, CFrame.Angles(math.rad(rot), 0, 0))
                    task.wait()
                else
                    setCF(tPart, CFrame.new(0, 1.5, tHum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, -1.5, -tHum.WalkSpeed), CFrame.Angles(0, 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, 1.5, tHum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                    task.wait()
                    setCF(tPart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                    task.wait()
                end
            end
        until startT + dur < tick() or not flingActive
    end

    local bv = Instance.new("BodyVelocity")
    bv.Parent = myRoot
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)

    myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

    if tRoot then
        flingLoop(tRoot)
    elseif tHead then
        flingLoop(tHead)
    elseif tHandle then
        flingLoop(tHandle)
    end

    bv:Destroy()
    myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
    workspace.CurrentCamera.CameraSubject = myHum

    if flingOldPos then
        myRoot.CFrame = flingOldPos
        myRoot.Velocity = Vector3.new(0, 0, 0)
        myRoot.RotVelocity = Vector3.new(0, 0, 0)
    end
end

local function flingMurderer(reason)
    if flingActive then return end
    local murderer = findMurderer()
    if not murderer then return end
    flingActive = true
    flingsTotal = flingsTotal + 1
    print("[FLING]", reason, murderer.Name)
    task.delay(15, function()
        if flingActive then flingActive = false end
    end)
    task.spawn(function()
        pcall(function() SkidFling(murderer) end)
        flingActive = false
        if workspace.CurrentCamera and player.Character then
            workspace.CurrentCamera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
        end
    end)
end

local function updateCharacterParts()
    characterParts = {}
    if not character then return end
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") then
            table.insert(characterParts, part)
        end
    end
end

local function restoreCollision()
    for _, part in ipairs(characterParts) do
        if part and part.Parent then
            part.CanCollide = true
        end
    end
end

local function cleanupConnections()
    if heartbeatConnection then heartbeatConnection:Disconnect() heartbeatConnection = nil end
    if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
    if coinAddedConnection then coinAddedConnection:Disconnect() coinAddedConnection = nil end
    if coinRemovedConnection then coinRemovedConnection:Disconnect() coinRemovedConnection = nil end
    if coinsStartedConnection then coinsStartedConnection:Disconnect() coinsStartedConnection = nil end
    if coinCollectedConnection then coinCollectedConnection:Disconnect() coinCollectedConnection = nil end
end

local function stopMovement()
    if linearVelocity then
        linearVelocity.VectorVelocity = Vector3.zero
        linearVelocity.Enabled = false
    end
    if rootPart then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function setupVelocity()
    if not rootPart then return end
    velocityAttachment = rootPart:FindFirstChild("FarmAttachment")
    if not velocityAttachment then
        velocityAttachment = Instance.new("Attachment")
        velocityAttachment.Name = "FarmAttachment"
        velocityAttachment.Parent = rootPart
    end
    linearVelocity = rootPart:FindFirstChild("FarmLinearVelocity")
    if not linearVelocity then
        linearVelocity = Instance.new("LinearVelocity")
        linearVelocity.Name = "FarmLinearVelocity"
        linearVelocity.Attachment0 = velocityAttachment
        linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
        linearVelocity.VectorVelocity = Vector3.zero
        linearVelocity.Enabled = false
        linearVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        linearVelocity.MaxAxesForce = Vector3.new(100000, 100000, 100000)
        linearVelocity.Parent = rootPart
    end
end

local function removeVelocity()
    if linearVelocity then linearVelocity:Destroy() linearVelocity = nil end
    if velocityAttachment then velocityAttachment:Destroy() velocityAttachment = nil end
end

local function startNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    updateCharacterParts()
    noclipConnection = RunService.Stepped:Connect(function()
        if character and enabled and humanoid and humanoid.Health > 0 and not bagIsFull and not isWaitingForCoins then
            for i = 1, #characterParts do
                local part = characterParts[i]
                if part and part.Parent and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
    if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    end
end

local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    restoreCollision()
end

local function antiAfkLoop()
    while afkActive and enabled do
        task.wait(30)
        if not afkActive or not enabled then break end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end

local function isCoin(part)
    if not part:IsA("BasePart") or blacklistedCoins[part] then return false end
    local name = part.Name:lower()
    return name:find("coin") or name:find("cash") or name:find("money") or name:find("collect")
end

local function checkGuiBagFull()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "AutoFarmUI" then
            local container = gui:FindFirstChild("Container", true)
            if container then
                for _, frame in ipairs(container:GetChildren()) do
                    if frame:IsA("Frame") and frame.Visible then
                        local fullIcon = frame:FindFirstChild("FullBagIcon", true)
                        local fullText = frame:FindFirstChild("Full", true)
                        if (fullIcon and fullIcon.Visible) or (fullText and fullText.Visible) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function trackCoin(part)
    if isCoin(part) then
        activeCoins[part] = true
    end
end

local function untrackCoin(part)
    activeCoins[part] = nil
    if currentTarget == part then
        currentTarget = nil
    end
end

local function triggerBagFullReset()
    if bagIsFull then return end
    bagIsFull = true
    stopMovement()
    stopNoclip()
    if flingBagFullEnabled then
        flingMurderer("bag_full")
        task.wait(2.5)
    end
    task.wait(0.2)
    if humanoid and humanoid.Health > 0 then
        humanoid.Health = 0
        resetsTotal = resetsTotal + 1
    end
end

local function initCoinListeners()
    activeCoins = {}
    for _, v in ipairs(Workspace:GetDescendants()) do
        if isCoin(v) then
            activeCoins[v] = true
        end
    end
    coinAddedConnection = Workspace.DescendantAdded:Connect(trackCoin)
    coinRemovedConnection = Workspace.DescendantRemoving:Connect(untrackCoin)
    if gameplayRemotes then
        local coinsStartedRemote = gameplayRemotes:WaitForChild("CoinsStarted", 5)
        local coinCollectedRemote = gameplayRemotes:WaitForChild("CoinCollected", 5)
        if coinsStartedRemote then
            coinsStartedConnection = coinsStartedRemote.OnClientEvent:Connect(function()
                isWaitingForCoins = true
                stopMovement()
                currentTarget = nil
                activeCoins = {}
                blacklistedCoins = {}
                noCoinsStartTime = nil
                bagIsFull = false
                task.wait(ROUND_START_DELAY)
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if isCoin(v) then
                        activeCoins[v] = true
                    end
                end
                isWaitingForCoins = false
            end)
        end
        if coinCollectedRemote then
            coinCollectedConnection = coinCollectedRemote.OnClientEvent:Connect(function(coinType, currentAmount, maxAmount)
                local current = tonumber(currentAmount)
                local max = tonumber(maxAmount)
                if current and max and current >= max then
                    triggerBagFullReset()
                end
            end)
        end
    end
end

local function startTargetFinder()
    if targetFinderThread then task.cancel(targetFinderThread) end
    targetFinderThread = task.spawn(function()
        while isLoaded do
            task.wait(0.1)
            if enabled and not bagIsFull and checkGuiBagFull() then
                triggerBagFullReset()
            end
            if enabled and not bagIsFull and not isWaitingForCoins and rootPart then
                local rootPos = rootPart.Position
                local nearest = nil
                local nearestDist = MAX_DIST + 1
                for coin, _ in pairs(activeCoins) do
                    if coin and coin.Parent and not blacklistedCoins[coin] then
                        local dist = (coin.Position - rootPos).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearest = coin
                        end
                    else
                        activeCoins[coin] = nil
                    end
                end
                if nearest and not nearest:FindFirstChild("CoinVisual") then
                    activeCoins[nearest] = nil
                    nearest = nil
                end
                currentTarget = nearest
            end
        end
    end)
end

local function startMovementEngine()
    cleanupConnections()
    setupVelocity()
    initCoinListeners()
    noCoinsStartTime = nil
    if enabled and not bagIsFull then startNoclip() end
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not enabled or bagIsFull or isWaitingForCoins or not rootPart or not rootPart.Parent or not humanoid or humanoid.Health <= 0 then
            stopMovement()
            return
        end
        if currentTarget and currentTarget.Parent and not blacklistedCoins[currentTarget] then
            noCoinsStartTime = nil
            local targetPos = currentTarget.Position
            local rootPos = rootPart.Position
            local dist = (targetPos - rootPos).Magnitude
            if dist <= 1.2 then
                rootPart.CFrame = CFrame.new(targetPos)
                stopMovement()
                hasCollectedThisLife = true
                coinsCollectedTotal = coinsCollectedTotal + 1
                blacklistedCoins[currentTarget] = true
                activeCoins[currentTarget] = nil
                currentTarget = nil
            else
                if linearVelocity then
                    linearVelocity.Enabled = true
                    linearVelocity.VectorVelocity = (targetPos - rootPos).Unit * TARGET_SPEED
                end
            end
        else
            stopMovement()
            if hasCollectedThisLife then
                if not noCoinsStartTime then
                    noCoinsStartTime = os.clock()
                elseif os.clock() - noCoinsStartTime >= RESET_DELAY then
                    noCoinsStartTime = nil
                    cleanupConnections()
                    humanoid.Health = 0
                    resetsTotal = resetsTotal + 1
                end
            else
                noCoinsStartTime = nil
            end
        end
    end)
end

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function sendWebhook()
    if webhookUrl == "" or not webhookUrl:find("https://discord.com/api/webhooks/") then return end
    local elapsed = os.time() - sessionStartTime
    local payload = {
        username = "AutoFarm Stats",
        embeds = {{
            title = "Farm Session Report",
            color = 3447003,
            fields = {
                { name = "Session Time", value = formatTime(elapsed), inline = true },
                { name = "Coins Collected", value = tostring(coinsCollectedTotal), inline = true },
                { name = "Flings", value = tostring(flingsTotal), inline = true },
                { name = "Resets", value = tostring(resetsTotal), inline = true },
                { name = "Player", value = player.Name, inline = true },
            },
            footer = { text = "AutoFarm by " .. player.Name },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }
    local body = HttpService:JSONEncode(payload)
    local ok, err = pcall(function()
        request({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
    if ok then
        lastWebhookTime = os.time()
    end
end

local function startWebhookLoop()
    if webhookThread then task.cancel(webhookThread) end
    webhookThread = task.spawn(function()
        while true do
            task.wait(WEBHOOK_INTERVAL)
            if webhookUrl ~= "" then
                sendWebhook()
            end
        end
    end)
end

local function unloadScript()
    isLoaded = false
    enabled = false
    afkActive = false
    bagIsFull = false
    isWaitingForCoins = false
    cleanupConnections()
    stopNoclip()
    removeVelocity()
    if targetFinderThread then
        task.cancel(targetFinderThread)
        targetFinderThread = nil
    end
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
        characterAddedConnection = nil
    end
    activeCoins = {}
    blacklistedCoins = {}
    currentTarget = nil
end

local function loadScript()
    if isLoaded then unloadScript() end
    isLoaded = true
    bagIsFull = false
    isWaitingForCoins = false
    character = player.Character or player.CharacterAdded:Wait()
    rootPart = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")
    blacklistedCoins = {}
    noCoinsStartTime = nil
    hasCollectedThisLife = false
    startTargetFinder()
    startMovementEngine()
    if characterAddedConnection then characterAddedConnection:Disconnect() end
    characterAddedConnection = player.CharacterAdded:Connect(function(newChar)
        cleanupConnections()
        removeVelocity()
        character = newChar
        rootPart = character:WaitForChild("HumanoidRootPart")
        humanoid = character:WaitForChild("Humanoid")
        blacklistedCoins = {}
        noCoinsStartTime = nil
        hasCollectedThisLife = false
        bagIsFull = false
        isWaitingForCoins = false
        if flingAfterDeathEnabled and isLoaded and enabled then
            task.spawn(function()
                task.wait(1.5)
                refreshRoles()
                flingMurderer("after_death")
            end)
        end
        task.wait(1.5)
        if isLoaded and enabled then
            startMovementEngine()
        end
    end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = player:WaitForChild("PlayerGui")
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 300, 0, 480)
Main.Position = UDim2.new(0.5, -150, 0.5, -240)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
Main.BackgroundTransparency = 0.05
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(80, 140, 255)
MainStroke.Thickness = 2
MainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundTransparency = 1
Header.Parent = Main

local CoinIcon = Instance.new("TextLabel")
CoinIcon.Size = UDim2.new(0, 20, 0, 20)
CoinIcon.Position = UDim2.new(0, 12, 0.5, -10)
CoinIcon.BackgroundTransparency = 1
CoinIcon.Text = "$"
CoinIcon.TextColor3 = Color3.fromRGB(255, 200, 50)
CoinIcon.Font = Enum.Font.GothamBold
CoinIcon.TextSize = 18
CoinIcon.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 150, 0, 20)
Title.Position = UDim2.new(0, 36, 0.5, -10)
Title.BackgroundTransparency = 1
Title.Text = "Coin Farm + Webhook"
Title.TextColor3 = Color3.fromRGB(230, 230, 245)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -32, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 60)
CloseBtn.BackgroundTransparency = 0.2
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(1, 13)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    unloadScript()
    ScreenGui:Destroy()
end)

local function createRow(yPos, labelText, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -16, 0, height or 40)
    row.Position = UDim2.new(0, 8, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
    row.BackgroundTransparency = 0.1
    row.BorderSizePixel = 0
    row.Parent = Main

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = row

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 140, 255)
    stroke.Thickness = 2
    stroke.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(220, 220, 240)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    return row
end

local function createToggle(parent, initialVal, callback)
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 44, 0, 24)
    toggle.Position = UDim2.new(1, -52, 0.5, -12)
    toggle.BackgroundColor3 = initialVal and Color3.fromRGB(100, 130, 255) or Color3.fromRGB(45, 45, 65)
    toggle.Text = ""
    toggle.BorderSizePixel = 0
    toggle.Parent = parent

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 12)
    toggleCorner.Parent = toggle

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = initialVal and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = toggle

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 9)
    knobCorner.Parent = knob

    local state = initialVal
    toggle.MouseButton1Click:Connect(function()
        state = not state
        local goalPos = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        local goalBg = state and Color3.fromRGB(100, 130, 255) or Color3.fromRGB(45, 45, 65)
        TweenService:Create(toggle, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = goalBg}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = goalPos}):Play()
        callback(state)
    end)
    return toggle
end

local Row1 = createRow(46, "Auto Farm")
createToggle(Row1, false, function(state)
    enabled = state
    if state then
        if not isLoaded then loadScript() end
        startMovementEngine()
        if afkActive then task.spawn(antiAfkLoop) end
    else
        stopMovement()
        stopNoclip()
        noCoinsStartTime = nil
    end
end)

local Row2 = createRow(94, "Anti-AFK")
createToggle(Row2, false, function(state)
    afkActive = state
    if state and enabled then task.spawn(antiAfkLoop) end
end)

local Row3 = createRow(142, "Fling Murderer (Bag Full)")
createToggle(Row3, false, function(state)
    flingBagFullEnabled = state
end)

local Row4 = createRow(190, "Fling Murderer (After Death)")
createToggle(Row4, false, function(state)
    flingAfterDeathEnabled = state
end)

local StatsLabel = Instance.new("TextLabel")
StatsLabel.Size = UDim2.new(1, -16, 0, 50)
StatsLabel.Position = UDim2.new(0, 8, 0, 238)
StatsLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
StatsLabel.BackgroundTransparency = 0.1
StatsLabel.Text = ""
StatsLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
StatsLabel.Font = Enum.Font.GothamMedium
StatsLabel.TextSize = 12
StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
StatsLabel.Parent = Main

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsLabel

local StatsStroke = Instance.new("UIStroke")
StatsStroke.Color = Color3.fromRGB(80, 140, 255)
StatsStroke.Thickness = 2
StatsStroke.Parent = StatsLabel

task.spawn(function()
    while ScreenGui.Parent do
        task.wait(1)
        local elapsed = os.time() - sessionStartTime
        StatsLabel.Text = string.format(
            "  Session: %s\n  Coins: %d\n  Flings: %d\n  Resets: %d",
            formatTime(elapsed), coinsCollectedTotal, flingsTotal, resetsTotal
        )
    end
end)

local WebhookRow = createRow(296, "Webhook URL", 60)

local WebhookBox = Instance.new("TextBox")
WebhookBox.Size = UDim2.new(1, -16, 0, 30)
WebhookBox.Position = UDim2.new(0, 8, 1, -35)
WebhookBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
WebhookBox.BackgroundTransparency = 0.2
WebhookBox.Text = ""
WebhookBox.PlaceholderText = "https://discord.com/api/webhooks/..."
WebhookBox.TextColor3 = Color3.fromRGB(220, 220, 240)
WebhookBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
WebhookBox.Font = Enum.Font.Gotham
WebhookBox.TextSize = 12
WebhookBox.TextXAlignment = Enum.TextXAlignment.Left
WebhookBox.ClearTextOnFocus = false
WebhookBox.Parent = WebhookRow

local WebhookCorner = Instance.new("UICorner")
WebhookCorner.CornerRadius = UDim.new(0, 6)
WebhookCorner.Parent = WebhookBox

WebhookBox.FocusLost:Connect(function()
    webhookUrl = WebhookBox.Text
    lastWebhookTime = os.time()
    if webhookUrl ~= "" then
        startWebhookLoop()
    end
end)

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.new(1, -16, 0, 30)
SendBtn.Position = UDim2.new(0, 8, 0, 364)
SendBtn.BackgroundColor3 = Color3.fromRGB(80, 130, 255)
SendBtn.Text = "Send Stats Now"
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextSize = 13
SendBtn.Parent = Main

local SendCorner = Instance.new("UICorner")
SendCorner.CornerRadius = UDim.new(0, 6)
SendCorner.Parent = SendBtn

SendBtn.MouseButton1Click:Connect(function()
    sendWebhook()
end)

local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, -16, 0, 40)
InfoLabel.Position = UDim2.new(0, 8, 0, 400)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text = "Auto-send every 30 min if URL is set"
InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.TextSize = 11
InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
InfoLabel.TextWrapped = true
InfoLabel.Parent = Main

local dragging, dragStart, startPos = false, nil, nil
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

loadScript()
