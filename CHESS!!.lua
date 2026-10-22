task.spawn(function() 
    local W=game:GetService("Workspace") 
    local CG=game:GetService("CoreGui") 
    local UIS=game:GetService("UserInputService") 
    local setcl=setclipboard or toclipboard 
    local pFolder=W:WaitForChild("Pieces") 
    local bFolder=W:WaitForChild("Board") 
    local acts={} 
    local turn="WHITE" 
    local history={} 
    local mCount=0 
    local pState={} 
    local PT={Pawn=1,Knight=2,Bishop=3,Rook=4,Queen=5,King=6} 
    local VAL={[1]=100,[2]=320,[3]=330,[4]=500,[5]=900,[6]=20000} 

    local MODES = {
        { name = "BALANCED", time = 3.0, color = Color3.fromRGB(60, 100, 60) },
        { name = "MATE",     time = 4.5, color = Color3.fromRGB(150, 80, 50) },
        { name = "GENOCIDE", time = 5.0, color = Color3.fromRGB(140, 20, 20) },
        { name = "ADAPTIVE", time = 60.0,color = Color3.fromRGB(80, 60, 150) },
        { name = "SOLID",    time = 4.0, color = Color3.fromRGB(60, 100, 180) },
    }
    local modeIdx = 1
    local MODE = MODES[modeIdx].name
    local TIME_BUDGET = MODES[modeIdx].time
    local botSignSearch = 1

    local bit32 = bit32 or bit 
    local bxor, band, bor = bit32.bxor, bit32.band, bit32.bor 
    local lshift, rshift = bit32.lshift, bit32.rshift 

    local SQ_X, SQ_Y = {}, {}
    for i=1,64 do SQ_X[i] = (i-1)%8+1; SQ_Y[i] = math.floor((i-1)/8)+1 end

    local zobrist = {}
    for i=1,64*12 do zobrist[i] = math.random(0, 2147483647) end
    local zobristSide = math.random(0, 2147483647)

    local function pieceIndex(pc) if pc > 0 then return pc else return -pc + 6 end end
    local function zIdx(i, p) return (i-1)*12 + p end

    local function computeHash(g, side)
        local h = 0
        for i=1,64 do
            local pc = g[i]
            if pc ~= 0 then h = bxor(h, zobrist[zIdx(i, pieceIndex(pc))]) end
        end
        if side == -1 then h = bxor(h, zobristSide) end
        return h
    end

    local cellPos, cellParts = {}, {}
    local boardReady = false
    local colorCache = setmetatable({}, {__mode="k"})

    local function hcall_safe_destroy(h) pcall(function() h:Destroy() end) end

    local function initBoard()
        if boardReady then return end
        local okAll = true
        for x=1,8 do for y=1,8 do
            local s = bFolder:FindFirstChild(x..","..y)
            if s then
                local ok, pos = pcall(function() return s:GetPivot().Position end)
                if not ok or not pos then
                    for _,c in ipairs(s:GetDescendants()) do
                        if c:IsA("BasePart") then pos = c.Position break end
                    end
                end
                if pos then
                    local idx = (y-1)*8+x
                    cellPos[idx] = Vector3.new(pos.X,0,pos.Z)
                    cellParts[idx] = s
                else okAll = false end
            else okAll = false end
        end end
        boardReady = okAll
    end

    local function clear() 
        for _,h in ipairs(acts) do if h then hcall_safe_destroy(h) end end 
        acts={} 
    end 

    local function findAdornee(obj)
        if not obj then return nil end
        if obj:IsA("BasePart") or obj:IsA("Model") then return obj end
        return obj:FindFirstChildWhichIsA("Model", true) or obj:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getCellCF(obj)
        if not obj then return nil, nil end
        if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
        if obj:IsA("Model") then
            local ok, cf, size = pcall(function() return obj:GetBoundingBox() end)
            if ok and cf and size and size.X > 0.1 and size.Z > 0.1 then return cf, size end
        end
        for _, c in ipairs(obj:GetDescendants()) do
            if c:IsA("BasePart") and c.Size.X > 0.1 and c.Size.Z > 0.1 then return c.CFrame, c.Size end
        end
        local ok, piv = pcall(function() return obj:GetPivot() end)
        if ok and piv then return piv, Vector3.new(4, 0.2, 4) end
        return nil, nil
    end

    local function placeFlatMarker(cf, size, col)
        local sx = (size and size.X) or 4
        local sz = (size and size.Z) or 4
        local sy = (size and size.Y) or 0.2
        local d = math.max(sx, sz) * 0.92
        if d < 0.5 then d = 3.7 end
        local p = Instance.new("Part")
        p.Name = "_MoveHL"
        p.Size = Vector3.new(d, 0.02, d)
        p.CFrame = cf * CFrame.new(0, sy/2 + 0.01, 0)
        p.Color = col
        p.Material = Enum.Material.Neon
        p.Anchored = true
        p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
        p.Transparency = 0.4
        p.Parent = W
        table.insert(acts, p)
    end

    local function addHighlight(adornee, col, fillTransp)
        if not adornee then return end
        local h = Instance.new("Highlight")
        h.FillColor = col; h.OutlineColor = col
        h.FillTransparency = fillTransp or 0.5
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = adornee; h.Parent = adornee
        table.insert(acts, h)
    end

    local function findCellByIndex(idx)
        if not idx then return nil end
        local cached = cellParts[idx]
        if cached and cached.Parent then return cached end
        local x = (idx-1)%8 + 1
        local y = math.floor((idx-1)/8) + 1
        local byName = bFolder:FindFirstChild(x..","..y)
        if byName then cellParts[idx] = byName return byName end
        if cellPos[idx] then
            local best, bestDist = nil, math.huge
            for _, c in ipairs(bFolder:GetChildren()) do
                local cf = getCellCF(c)
                if cf then
                    local flat = Vector3.new(cf.Position.X, 0, cf.Position.Z)
                    local d = (flat - cellPos[idx]).Magnitude
                    if d < bestDist then bestDist = d; best = c end
                end
            end
            if best and bestDist < 4 then cellParts[idx] = best return best end
        end
        return nil
    end

    local function hlCell(obj, col, idx)
        if not obj and idx then obj = findCellByIndex(idx) end
        if obj then
            local adornee = findAdornee(obj)
            if adornee then addHighlight(adornee, col, 0.55) end
            local cf, size = getCellCF(obj)
            if cf then placeFlatMarker(cf, size or Vector3.new(4,0.2,4), col); return true end
        end
        if idx and cellPos[idx] then
            placeFlatMarker(CFrame.new(cellPos[idx]), Vector3.new(4, 0.2, 4), col)
            return true
        end
        return false
    end

    local function hlPiece(obj, col)
        if not obj then return false end
        local adornee = findAdornee(obj)
        if adornee then addHighlight(adornee, col, 0.5); return true end
        return false
    end

    local function getColInfo(p)
        local count = 0
        local maxVol = 0
        local mainPart = nil
        for _, c in ipairs(p:GetDescendants()) do
            if (c:IsA("MeshPart") or c:IsA("Part")) and c.Transparency < 0.9 then
                count = count + 1
                local vol = c.Size.X * c.Size.Y * c.Size.Z
                if vol > maxVol then maxVol = vol; mainPart = c end
            end
        end
        if not mainPart then return nil, 0 end
        local color = mainPart.Color
        local partColor
        if color.R > 0.85 and color.G > 0.85 and color.B > 0.85 then partColor = 1
        elseif color.R < 0.15 and color.G < 0.15 and color.B < 0.15 then partColor = -1
        else
            local b = (color.R + color.G + color.B) / 3
            partColor = (b > 0.5) and 1 or -1
        end
        return partColor, count
    end

    local function getColCached(p)
        local cached = colorCache[p]
        if cached then return cached.partColor end
        local partColor, count = getColInfo(p)
        if not partColor then return nil end
        colorCache[p] = { partColor = partColor, count = count }
        return partColor
    end

    local function scanBoard() 
        initBoard()
        local g={} for i=1,64 do g[i]=0 end 
        local models={} 
        local kings = {}
        for _,p in ipairs(pFolder:GetChildren()) do 
            if p:IsA("Model") and PT[p.Name] then 
                local pPos=p:GetPivot().Position 
                local pFlat=Vector3.new(pPos.X,0,pPos.Z) 
                local bIdx,bDist=nil,math.huge 
                for i=1,64 do 
                    if cellPos[i] then 
                        local dist=(cellPos[i]-pFlat).Magnitude 
                        if dist<bDist then bDist=dist bIdx=i end 
                    end 
                end 
                if bIdx and bDist<6 then 
                    local c = getColCached(p)
                    local pt = PT[p.Name]
                    if c then g[bIdx]=pt*c; models[bIdx]=p end 
                    if pt == 6 and c then table.insert(kings, {model=p, idx=bIdx, color=c}) end 
                end 
            end 
        end 
        return g, models, kings 
    end 

    local function fixKings(g, models, kings)
        if #kings < 2 then return false, false end
        local botSign = (turn=="WHITE") and 1 or -1
        local botKing, enemyKing, rest = nil, nil, {}
        for _,k in ipairs(kings) do
            if not botKing and k.color == botSign then botKing = k
            else table.insert(rest, k) end
        end
        if not botKing and #rest > 0 then botKing = rest[1]; table.remove(rest, 1) end
        if #rest > 0 then enemyKing = rest[1] end
        if botKing then g[botKing.idx] = 6 * botSign; models[botKing.idx] = botKing.model end
        if enemyKing then g[enemyKing.idx] = -6 * botSign; models[enemyKing.idx] = enemyKing.model end
        return botKing ~= nil, enemyKing ~= nil
    end

    local PST_RAW = {
        [1] = {
              0,  0,  0,  0,  0,  0,  0,  0,
              5, 10, 10,-20,-20, 10, 10,  5,
              5, -5,-10,  0,  0,-10, -5,  5,
              0,  0,  0, 20, 20,  0,  0,  0,
              5,  5, 10, 25, 25, 10,  5,  5,
             10, 10, 20, 30, 30, 20, 10, 10,
             50, 50, 50, 50, 50, 50, 50, 50,
              0,  0,  0,  0,  0,  0,  0,  0,
        },
        [2] = {
            -50,-40,-30,-30,-30,-30,-40,-50,
            -40,-20,  0,  0,  0,  0,-20,-40,
            -30,  0, 10, 15, 15, 10,  0,-30,
            -30,  5, 15, 20, 20, 15,  5,-30,
            -30,  0, 15, 20, 20, 15,  0,-30,
            -30,  5, 10, 15, 15, 10,  5,-30,
            -40,-20,  0,  5,  5,  0,-20,-40,
            -50,-40,-30,-30,-30,-30,-40,-50,
        },
        [3] = {
            -20,-10,-10,-10,-10,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5, 10, 10,  5,  0,-10,
            -10,  5,  5, 10, 10,  5,  5,-10,
            -10,  0, 10, 10, 10, 10,  0,-10,
            -10, 10, 10, 10, 10, 10, 10,-10,
            -10,  5,  0,  0,  0,  0,  5,-10,
            -20,-10,-10,-10,-10,-10,-10,-20,
        },
        [4] = {
              0,  0,  0,  0,  0,  0,  0,  0,
              5, 10, 10, 10, 10, 10, 10,  5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
              0,  0,  0,  5,  5,  0,  0,  0,
        },
        [5] = {
            -20,-10,-10, -5, -5,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5,  5,  5,  5,  0,-10,
             -5,  0,  5,  5,  5,  5,  0, -5,
              0,  0,  5,  5,  5,  5,  0, -5,
            -10,  5,  5,  5,  5,  5,  0,-10,
            -10,  0,  5,  0,  0,  0,  0,-10,
            -20,-10,-10, -5, -5,-10,-10,-20,
        },
        [6] = {
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -20,-30,-30,-40,-40,-30,-30,-20,
            -10,-20,-20,-20,-20,-20,-20,-10,
             20, 20,  0,  0,  0,  0, 20, 20,
             20, 30, 10,  0,  0, 10, 30, 20,
        },
    }
    local PST = {}
    for pt=1,6 do
        PST[pt] = {[1]={},[-1]={}}
        for cSign in pairs({[1]=true, [-1]=true}) do
            for i=1,64 do
                if cSign == 1 then
                    PST[pt][1][i] = PST_RAW[pt][i]
                else
                    local x = (i-1)%8
                    local y = math.floor((i-1)/8)
                    local mi = (7-y)*8 + x + 1
                    PST[pt][-1][i] = PST_RAW[pt][mi]
                end
            end
        end
    end

    local function evalBoard(g, side)
        local matPST = 0
        local wB, bB = 0, 0
        local wP, bP = {}, {}
        local wpFiles = {0,0,0,0,0,0,0,0}
        local bpFiles = {0,0,0,0,0,0,0,0}
        local wPieces = 0
        local bPieces = 0
        local wK, bK = -1, -1

        local matMult = (MODE == "SOLID") and 1.2 or 1.0

        for i=1,64 do
            local pc = g[i]
            if pc ~= 0 then
                wPieces = wPieces + (pc > 0 and 1 or 0)
                bPieces = bPieces + (pc < 0 and 1 or 0)
                local pt = pc > 0 and pc or -pc
                local cSign = pc > 0 and 1 or -1
                
                local val = VAL[pt] * (pt == 6 and 1.0 or matMult) + PST[pt][cSign][i]
                
                if pc > 0 then matPST = matPST + val else matPST = matPST - val end
                if pt == 1 then
                    local x = SQ_X[i]
                    if pc > 0 then wpFiles[x] = wpFiles[x]+1; wP[#wP+1] = {x=x, y=SQ_Y[i], i=i}
                    else bpFiles[x] = bpFiles[x]+1; bP[#bP+1] = {x=x, y=SQ_Y[i], i=i} end
                elseif pt == 3 then
                    if pc > 0 then wB = wB + 1 else bB = bB + 1 end
                elseif pt == 6 then
                    if pc > 0 then wK = i else bK = i end
                end
            end
        end

        if wPieces <= 2 and bPieces <= 2 then
            if wB == 0 and bB == 0 then
                local wN, bN = 0, 0
                for i=1,64 do
                    if g[i] == 2 then wN = wN + 1 elseif g[i] == -2 then bN = bN + 1 end
                end
                if wN + wB + bN + bB <= 1 then return 0 end
            end
        end

        local score = matPST
        if wB >= 2 then score = score + 30 end
        if bB >= 2 then score = score - 30 end

        for x=1,8 do
            local wc, bc = wpFiles[x], bpFiles[x]
            if wc > 1 then score = score - (wc-1) * 15 end
            if bc > 1 then score = score + (bc-1) * 15 end
            local wl = (x == 1) and 0 or wpFiles[x-1]
            local wr = (x == 8) and 0 or wpFiles[x+1]
            local bl = (x == 1) and 0 or bpFiles[x-1]
            local br = (x == 8) and 0 or bpFiles[x+1]
            if wc > 0 and wl == 0 and wr == 0 then score = score - 20 * wc end
            if bc > 0 and bl == 0 and br == 0 then score = score + 20 * bc end
        end

        for _, p in ipairs(wP) do
            local isPassed = true
            for _, op in ipairs(bP) do
                if math.abs(op.x - p.x) <= 1 and op.y > p.y then isPassed = false; break end
            end
            if isPassed then score = score + (p.y - 2) * 10 end
        end
        for _, p in ipairs(bP) do
            local isPassed = true
            for _, wp in ipairs(wP) do
                if math.abs(wp.x - p.x) <= 1 and wp.y < p.y then isPassed = false; break end
            end
            if isPassed then score = score - (7 - p.y) * 10 end
        end

        if wK ~= -1 then
            local x, y = SQ_X[wK], SQ_Y[wK]
            local shield = 0
            if y >= 2 then
                for dx=-1,1 do
                    if x+dx >= 1 and x+dx <= 8 then
                        local idx = (y-2)*8 + x+dx
                        if g[idx] == 1 then shield = shield + 10 end
                    end
                end
            end
            score = score + shield
        end
        if bK ~= -1 then
            local x, y = SQ_X[bK], SQ_Y[bK]
            local shield = 0
            if y <= 7 then
                for dx=-1,1 do
                    if x+dx >= 1 and x+dx <= 8 then
                        local idx = y*8 + x+dx
                        if g[idx] == -1 then shield = shield + 10 end
                    end
                end
            end
            score = score - shield
        end

        if MODE == "MATE" then
            local eK
            if side > 0 then eK = bK else eK = wK end
            if eK ~= -1 then
                local ex, ey = SQ_X[eK], SQ_Y[eK]
                local attackBonus = 0
                for i=1,64 do
                    local pc = g[i]
                    if pc * side > 0 and math.abs(pc) ~= 6 and math.abs(pc) ~= 1 then
                        local dx = math.abs(SQ_X[i] - ex)
                        local dy = math.abs(SQ_Y[i] - ey)
                        local dist = math.max(dx, dy)
                        if dist <= 3 then attackBonus = attackBonus + (4 - dist) * 8 end
                    end
                end
                score = score + attackBonus
            end
        elseif MODE == "SOLID" then
            if wK ~= -1 then
                local wk_y = SQ_Y[wK]
                if wk_y > 3 then score = score - 250 end
            end
            if bK ~= -1 then
                local bk_y = SQ_Y[bK]
                if bk_y < 6 then score = score + 250 end
            end
        end

        return score * side
    end

    local function isAttacked(g,opp,tx,ty) 
        local py=(opp==1) and ty-1 or ty+1 
        if tx>1 and py>=1 and py<=8 and g[(py-1)*8+tx-1]==1*opp then return true end 
        if tx<8 and py>=1 and py<=8 and g[(py-1)*8+tx+1]==1*opp then return true end 
        for _,d in ipairs({{2,1},{2,-1},{-2,1},{-2,-1},{1,2},{1,-2},{-1,2},{-1,-2}}) do 
            local nx,ny=tx+d[1],ty+d[2] 
            if nx>=1 and nx<=8 and ny>=1 and ny<=8 and g[(ny-1)*8+nx]==2*opp then return true end 
        end 
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}) do 
            local nx,ny=tx+d[1],ty+d[2] 
            if nx>=1 and nx<=8 and ny>=1 and ny<=8 and g[(ny-1)*8+nx]==6*opp then return true end 
        end 
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do 
            local cx,cy=tx+d[1],ty+d[2] 
            while cx>=1 and cx<=8 and cy>=1 and cy<=8 do 
                local pc=g[(cy-1)*8+cx] 
                if pc~=0 then if pc==4*opp or pc==5*opp then return true end break end 
                cx,cy=cx+d[1],cy+d[2] 
            end 
        end 
        for _,d in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do 
            local cx,cy=tx+d[1],ty+d[2] 
            while cx>=1 and cx<=8 and cy>=1 and cy<=8 do 
                local pc=g[(cy-1)*8+cx] 
                if pc~=0 then if pc==3*opp or pc==5*opp then return true end break end 
                cx,cy=cx+d[1],cy+d[2] 
            end 
        end 
        return false 
    end 

    local function isInCheck(g,color) 
        for i=1,64 do 
            if g[i]==6*color then return isAttacked(g,-color,SQ_X[i],SQ_Y[i]) end 
        end 
        return false 
    end 

    local function packMove(from, to, score)
        if score < 0 then score = 0 end
        return bor(bor(from-1, lshift(to-1, 6)), lshift(score, 12))
    end
    local function moveFrom(mv) return band(mv, 0x3F) + 1 end
    local function moveTo(mv) return band(rshift(mv, 6), 0x3F) + 1 end
    local function moveCore(mv) return band(mv, 0xFFF) end

    local TT_MOVE_SCORE  = 250000
    local CAPTURE_BASE   = 100000
    local KILLER_BASE    = 50000
    local HIST_CAP       = 40000

    local killers = {}
    local histTable = {}
    for p=1,6 do histTable[p] = {} for t=1,64 do histTable[p][t] = 0 end end

    local function genMoves(g, side, onlyCaps, ttMove, ply) 
        local m = {} 
        local ttCore = ttMove and moveCore(ttMove) or 0
        local k1, k2 = 0, 0
        if ply then
            local k = killers[ply]
            if k then k1 = k[1] or 0; k2 = k[2] or 0 end
        end
        local function score(from, to)
            local core = bor(from-1, lshift(to-1, 6))
            if ttCore ~= 0 and core == ttCore then return TT_MOVE_SCORE end
            local victim = g[to]
            if victim ~= 0 then
                local attacker = math.abs(g[from])
                local av = VAL[attacker]; if av > 500 then av = 500 end
                return CAPTURE_BASE + VAL[math.abs(victim)] - av
            end
            if core == k1 then return KILLER_BASE + 100 end
            if core == k2 then return KILLER_BASE + 50 end
            local attacker = math.abs(g[from])
            local hv = histTable[attacker][to] or 0
            if hv > HIST_CAP then hv = HIST_CAP end
            return hv
        end
        local function push(from, to, bonus)
            m[#m+1] = packMove(from, to, score(from, to) + (bonus or 0))
        end
        for i=1,64 do 
            local pc=g[i] 
            if pc*side>0 then 
                local pt=math.abs(pc) 
                local x=SQ_X[i]; local y=SQ_Y[i]
                if pt==1 then 
                    local ny=y+side 
                    if ny>=1 and ny<=8 then 
                        local ni=(ny-1)*8+x 
                        if not onlyCaps and g[ni]==0 then 
                            local bScore = (mCount<=2 and (x==4 or x==5) and math.abs(y-ny)==2) and 50 or 0
                            push(i, ni, bScore)
                            if (side==1 and y==2) or (side==-1 and y==7) then 
                                local ni2=(y+2*side-1)*8+x 
                                if g[ni2]==0 then push(i, ni2, bScore) end 
                            end 
                        end 
                        if x>1 then local cap=(ny-1)*8+x-1 if g[cap]*side<0 then push(i, cap) end end 
                        if x<8 then local cap=(ny-1)*8+x+1 if g[cap]*side<0 then push(i, cap) end end 
                    end 
                elseif pt==2 then 
                    for _,d in ipairs({{2,1},{2,-1},{-2,1},{-2,-1},{1,2},{1,-2},{-1,2},{-1,-2}}) do 
                        local nx,ny=x+d[1],y+d[2] 
                        if nx>=1 and nx<=8 and ny>=1 and ny<=8 then 
                            local ni=(ny-1)*8+nx local tgt=g[ni] 
                            if tgt*side<=0 and (not onlyCaps or tgt~=0) then push(i, ni) end 
                        end 
                    end 
                elseif pt==6 then 
                    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}) do 
                        local nx,ny=x+d[1],y+d[2] 
                        if nx>=1 and nx<=8 and ny>=1 and ny<=8 then 
                            local ni=(ny-1)*8+nx local tgt=g[ni] 
                            if tgt*side<=0 and (not onlyCaps or tgt~=0) then push(i, ni) end 
                        end 
                    end 
                else 
                    local dirs={} 
                    if pt==4 or pt==5 then for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do table.insert(dirs,d) end end 
                    if pt==3 or pt==5 then for _,d in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do table.insert(dirs,d) end end 
                    for _,d in ipairs(dirs) do 
                        local cx,cy=x+d[1],y+d[2] 
                        while cx>=1 and cx<=8 and cy>=1 and cy<=8 do 
                            local ni=(cy-1)*8+cx local tgt=g[ni] 
                            if tgt==0 then 
                                if not onlyCaps then push(i, ni) end
                            elseif tgt*side<0 then 
                                push(i, ni) break 
                            else break end 
                            cx,cy=cx+d[1],cy+d[2] 
                        end 
                    end 
                end 
            end 
        end 
        table.sort(m,function(a,b) return a>b end) 
        return m 
    end 

    local function makeMove(g, mv, hash)
        local from = band(mv, 0x3F) + 1
        local to   = band(rshift(mv, 6), 0x3F) + 1
        local movingPiece = g[from]
        local cap = g[to]
        hash = bxor(hash, zobrist[zIdx(from, pieceIndex(movingPiece))])
        if cap ~= 0 then hash = bxor(hash, zobrist[zIdx(to, pieceIndex(cap))]) end
        hash = bxor(hash, zobrist[zIdx(to, pieceIndex(movingPiece))])
        hash = bxor(hash, zobristSide)
        g[to] = movingPiece; g[from] = 0
        return cap, hash
    end
    
    local function unmakeMove(g, mv, cap)
        local from = band(mv, 0x3F) + 1
        local to   = band(rshift(mv, 6), 0x3F) + 1
        g[from] = g[to]; g[to] = cap
    end

    local TT = {}
    local FLAG_EXACT, FLAG_LOWER, FLAG_UPPER = 0, 1, 2
    local function ttSet(hash, entry)
        local old = TT[hash]
        if old and old.depth > entry.depth then return end
        TT[hash] = entry
    end

    local startTime = 0
    local nodeCount = 0
    local stopSearch = false
    local gameHashes = {}

    local function quiesce(g, alpha, beta, color, hash, qDepth)
        if stopSearch or qDepth > 8 then return evalBoard(g, color) end
        nodeCount = nodeCount + 1
        
        if nodeCount % 5000 == 0 then task.wait() end

        if nodeCount % 1024 == 0 and os.clock() - startTime > TIME_BUDGET then 
            stopSearch = true; return evalBoard(g, color) 
        end
        local standPat = evalBoard(g, color) 
        if standPat >= beta then return beta end 
        if alpha < standPat then alpha = standPat end 
        local m = genMoves(g, color, true, nil, nil) 
        for _,mv in ipairs(m) do 
            if stopSearch then break end
            local victimVal = VAL[math.abs(g[moveTo(mv)])]
            if standPat + victimVal + 200 >= alpha then
                local cap, newHash = makeMove(g, mv, hash) 
                if not isInCheck(g,color) then 
                    local score = -quiesce(g, -beta, -alpha, -color, newHash, qDepth + 1) 
                    unmakeMove(g,mv,cap) 
                    if score >= beta then return beta end 
                    if score > alpha then alpha = score end 
                else unmakeMove(g,mv,cap) end 
            end
        end 
        return alpha 
    end 

    local function minimax(g, depth, alpha, beta, color, hash, ply) 
        if stopSearch then return evalBoard(g, color), nil end
        nodeCount = nodeCount + 1
        
        if nodeCount % 5000 == 0 then task.wait() end

        if nodeCount % 1024 == 0 and os.clock() - startTime > TIME_BUDGET then 
            stopSearch = true; return evalBoard(g,color), nil 
        end

        if gameHashes[hash] and gameHashes[hash] >= 2 then return 0, nil end

        local origAlpha = alpha
        local ttEntry = TT[hash]
        local ttMove = 0
        if ttEntry then
            ttMove = ttEntry.move
            if ttEntry.depth >= depth then
                local sc = ttEntry.score
                if ttEntry.flag == FLAG_EXACT then return sc, ttMove end
                if ttEntry.flag == FLAG_LOWER and sc >= beta then return sc, ttMove end
                if ttEntry.flag == FLAG_UPPER and sc <= alpha then return sc, ttMove end
            end
        end
        if depth <= 0 then return quiesce(g, alpha, beta, color, hash, 0), nil end 
        
        local inCheck = isInCheck(g, color)
        if inCheck then depth = depth + 1 end
        
        if depth >= 3 and ply > 0 and not inCheck then
            local hasMaterial = false
            for i=1,64 do
                local pc = g[i]
                if pc*color > 0 then
                    local pt = math.abs(pc)
                    if pt ~= 1 and pt ~= 6 then hasMaterial = true break end
                end
            end
            if hasMaterial then
                local R = (depth > 6) and 3 or 2
                local nullHash = bxor(hash, zobristSide)
                local nullScore = -minimax(g, depth - 1 - R, -beta, -beta + 1, -color, nullHash, ply + 1)
                if stopSearch then return evalBoard(g, color), nil end
                if nullScore >= beta then return beta, nil end
            end
        end
        
        local futility = false
        if depth == 1 and not inCheck and alpha > -90000 and alpha < 90000 then
            local se = evalBoard(g, color)
            if se + 250 <= alpha then futility = true end
        end
        
        local m = genMoves(g, color, false, ttMove ~= 0 and ttMove or nil, ply) 
        if #m == 0 then 
            local sc
            if inCheck then
                local baseMate = -999999 + (10-depth)*1000
                if MODE == "MATE" then
                    sc = baseMate * 2
                elseif MODE == "GENOCIDE" then
                    if color == -botSignSearch then
                        local victimsLeft = 0
                        for i=1,64 do
                            local pc = g[i]
                            if pc * color > 0 and math.abs(pc) ~= 6 then victimsLeft = victimsLeft + 1 end
                        end
                        if victimsLeft > 0 then sc = -50 else sc = baseMate * 2 end
                    else
                        sc = baseMate
                    end
                else
                    sc = baseMate
                end
            else
                sc = 0
            end
            ttSet(hash, {depth=depth, score=sc, flag=FLAG_EXACT, move=0})
            return sc, nil 
        end 
        local bestM = 0
        local legalMoveCount = 0
        for _,mv in ipairs(m) do 
            if stopSearch then break end
            local isCapture = g[moveTo(mv)] ~= 0
            
            if (futility and not isCapture) then
            elseif (depth <= 2) and not isCapture and not inCheck and legalMoveCount > 6 + depth*3 then
            else
                local cap, newHash = makeMove(g, mv, hash) 
                if not isInCheck(g,color) then 
                    legalMoveCount = legalMoveCount + 1
                    gameHashes[newHash] = (gameHashes[newHash] or 0) + 1
                    
                    local score
                    local reduce = 0
                    if depth >= 3 and legalMoveCount > 4 and cap == 0 then
                        reduce = 1
                        if depth >= 5 and legalMoveCount > 8 then reduce = 2 end
                    end
                    if legalMoveCount == 1 then
                        score = -minimax(g, depth-1, -beta, -alpha, -color, newHash, ply + 1) 
                    else
                        score = -minimax(g, depth-1-reduce, -alpha-1, -alpha, -color, newHash, ply + 1) 
                        if reduce > 0 and score > alpha then
                            score = -minimax(g, depth-1, -alpha-1, -alpha, -color, newHash, ply + 1)
                        end
                        if score > alpha and score < beta then
                            score = -minimax(g, depth-1, -beta, -alpha, -color, newHash, ply + 1) 
                        end
                    end
                    
                    gameHashes[newHash] = gameHashes[newHash] - 1
                    if gameHashes[newHash] <= 0 then gameHashes[newHash] = nil end
                    
                    unmakeMove(g,mv,cap) 
                    if stopSearch then break end
                    if score > alpha then alpha = score; bestM = mv end 
                    if alpha >= beta then 
                        if cap == 0 and ply then
                            local core = moveCore(mv)
                            local k = killers[ply]
                            if not k then k = {0,0}; killers[ply] = k end
                            if k[1] ~= core then k[2] = k[1]; k[1] = core end
                            local f = moveFrom(mv); local t = moveTo(mv)
                            local pt = math.abs(g[f])
                            histTable[pt][t] = histTable[pt][t] + depth*depth
                        end
                        break 
                    end 
                else unmakeMove(g,mv,cap) end 
            end
        end 
        if legalMoveCount == 0 then 
            if stopSearch then return evalBoard(g, color), nil end
            local sc = inCheck and (-999999+(10-depth)*1000) or 0
            ttSet(hash, {depth=depth, score=sc, flag=FLAG_EXACT, move=0})
            return sc, nil 
        end
        if not stopSearch then
            local flag
            if alpha <= origAlpha then flag = FLAG_UPPER
            elseif alpha >= beta then flag = FLAG_LOWER
            else flag = FLAG_EXACT end
            ttSet(hash, {depth=depth, score=alpha, flag=flag, move=bestM})
        end
        return alpha, bestM ~= 0 and bestM or nil
    end 

    local LINES = {}
    local LINES_COUNT = 0
    local LINES_MAX_TOTAL = 80000
    local LINES_PER_HASH = 3
    local LINES_MIN_DEPTH = 6

    local function addLine(hash, move, score, depth)
        if depth < LINES_MIN_DEPTH then return end
        local list = LINES[hash]
        if not list then list = {}; LINES[hash] = list; LINES_COUNT = LINES_COUNT + 1 end
        for _, e in ipairs(list) do
            if e.move == move then
                if depth > e.depth then e.depth = depth end
                if math.abs(score) > math.abs(e.score) then e.score = score end
                return
            end
        end
        list[#list+1] = { move = move, score = score, depth = depth }
        table.sort(list, function(a, b) if a.depth ~= b.depth then return a.depth > b.depth end return a.score > b.score end)
        while #list > LINES_PER_HASH do table.remove(list) end
        if LINES_COUNT > LINES_MAX_TOTAL then
            local removed = 0
            for k in pairs(LINES) do
                LINES[k] = nil; LINES_COUNT = LINES_COUNT - 1; removed = removed + 1
                if removed >= math.floor(LINES_MAX_TOTAL * 0.3) then break end
            end
        end
    end

    local function getLineMove(hash, g, side)
        local list = LINES[hash]
        if not list then return nil end
        for _, e in ipairs(list) do
            local from = band(e.move, 0x3F) + 1
            local to   = band(rshift(e.move, 6), 0x3F) + 1
            local pc = g[from]; local tgt = g[to]
            if pc ~= 0 and pc*side > 0 and tgt*side <= 0 then
                g[to] = pc; g[from] = 0
                local bad = isInCheck(g, side)
                g[from] = pc; g[to] = tgt
                if not bad then return e.move, e.depth, e.score end
            end
        end
        return nil
    end

    local function walkPV(g, hash, side, maxLen)
        local pv, saved = {}, {}
        local curHash, curSide = hash, side
        for _ = 1, maxLen do
            local entry = TT[curHash]
            if not entry or entry.move == 0 then break end
            local from = moveFrom(entry.move); local to = moveTo(entry.move)
            local pc = g[from]
            if pc == 0 or pc * curSide <= 0 then break end
            local cap = g[to]
            if cap * curSide > 0 then break end
            if gameHashes[curHash] then break end
            
            pv[#pv+1] = { hash = curHash, move = entry.move, score = entry.score, depth = entry.depth }
            
            curHash = bxor(curHash, zobrist[zIdx(from, pieceIndex(pc))])
            if cap ~= 0 then curHash = bxor(curHash, zobrist[zIdx(to, pieceIndex(cap))]) end
            curHash = bxor(curHash, zobrist[zIdx(to, pieceIndex(pc))])
            curHash = bxor(curHash, zobristSide)
            g[to] = pc; g[from] = 0
            saved[#saved+1] = { from=from, to=to, cap=cap }
            curSide = -curSide
        end
        for i = #saved, 1, -1 do
            local s = saved[i]
            g[s.from] = g[s.to]; g[s.to] = s.cap
        end
        return pv
    end

    local function detectOpp(cur) 
        if not next(pState) then return end 
        local oppCol=(turn=="WHITE") and -1 or 1 
        local curPos={} 
        for i=1,64 do local c=cur[i] if c and c*oppCol>0 then curPos[i]=c end end 
        for i=1,64 do 
            local prev=pState[i] 
            if prev and prev*oppCol>0 and not curPos[i] then 
                for j=1,64 do 
                    if curPos[j]==prev then 
                        mCount=mCount+1 
                        local fx=SQ_X[i] local fy=SQ_Y[i]
                        local tx=SQ_X[j] local ty=SQ_Y[j]
                        history[#history+1]=string.format("[Move %d] %s: (%d,%d)->(%d,%d) [Opp]",mCount,(turn=="WHITE") and "BLACK" or "WHITE",fx,fy,tx,ty) 
                        curPos[j]=nil break 
                    end 
                end 
            end 
        end 
    end 

    local function getColorSign() return (turn=="WHITE") and 1 or -1 end 

    local function play() 
        clear() 
        local g,models,kings = scanBoard() 
        local okBot, okEnemy = fixKings(g, models, kings)
        if not okBot or not okEnemy then 
            print("[BOT] WARNING: Kings not found!")
            return 
        end 
        detectOpp(g) 
        local side = getColorSign() 
        botSignSearch = side
        local hash = computeHash(g, side)
        
        gameHashes = { [hash] = 1 }

        local best, bestScore, finalDepth, elapsed = nil, -math.huge, 0, 0
        local fromLine = false
        
        if MODE ~= "GENOCIDE" then
            local lineMove, lineDepth, lineScore = getLineMove(hash, g, side)
            if lineMove and lineDepth >= 8 and lineScore >= 0 then
                best = lineMove; bestScore = lineScore; finalDepth = lineDepth
                fromLine = true; elapsed = 0
            end
        end

        if not best then
            startTime = os.clock() 
            nodeCount = 0; stopSearch = false
            killers = {}
            for p=1,6 do for t=1,64 do histTable[p][t] = math.floor(histTable[p][t] / 2) end end
            
            local prevBestMove1 = 0
            local prevBestMove2 = 0
            local maxD = (MODE == "ADAPTIVE") and 25 or 20
            
            for d = 2, maxD do
                local delta = 50
                local alpha, beta = -math.huge, math.huge
                if d > 2 and bestScore > -90000 and bestScore < 90000 then
                    alpha = bestScore - delta; beta  = bestScore + delta
                end
                local currentBestMove = nil
                local currentScore = -math.huge
                while true do
                    local score, move = minimax(g, d, alpha, beta, side, hash, 0)
                    if stopSearch then break end
                    if score <= alpha then
                        alpha = math.max(-math.huge, alpha - delta); delta = delta * 2
                    elseif score >= beta then
                        beta = math.min(math.huge, beta + delta); delta = delta * 2
                    else
                        currentBestMove = move; currentScore = score; break
                    end
                end
                if stopSearch then break end
                
                if currentBestMove then 
                    best = currentBestMove
                    bestScore = currentScore
                    finalDepth = d 
                end
                
                elapsed = os.clock() - startTime

                if MODE == "ADAPTIVE" and d >= 8 then
                    if best == prevBestMove1 and best == prevBestMove2 then
                        break
                    end
                    prevBestMove2 = prevBestMove1
                    prevBestMove1 = best
                end
                
                local limitFactor = (MODE == "ADAPTIVE") and 0.95 or 0.55
                if elapsed > TIME_BUDGET * limitFactor then break end
                
                if bestScore > 90000 or bestScore < -90000 then break end
            end
            elapsed = os.clock() - startTime

            if best then
                local pv = walkPV(g, hash, side, 12)
                for _, e in ipairs(pv) do
                    if e.score >= 0 then addLine(e.hash, e.move, e.score, e.depth) end
                end
            end
        end

        if best then 
            local from = moveFrom(best); local to = moveTo(best)
            local tx = SQ_X[to]; local ty = SQ_Y[to]
            
            local targetCell = bFolder:FindFirstChild(tx..","..ty)
            local okCell = hlCell(targetCell, Color3.fromRGB(0,255,0), to)
            if not okCell then print(string.format("[BOT] WARN: Cell %d,%d not highlighted", tx, ty)) end
            
            local model = models[from]
            local okPiece = hlPiece(model, Color3.fromRGB(0,100,255))
            if not okPiece then print(string.format("[BOT] WARN: Piece idx=%d not highlighted", from)) end
            
            mCount=mCount+1 
            local fx = SQ_X[from]; local fy = SQ_Y[from]
            local tag = fromLine and "[LINE]" or "[Bot]"
            local logStr
            if fromLine then
                logStr = string.format("[%s][Move %d] %s: (%d,%d)->(%d,%d) | Depth=%d Score=%.0f | 0.00s %s",
                    MODE, mCount, turn, fx, fy, tx, ty, finalDepth, bestScore, tag)
            else
                logStr = string.format("[%s][Move %d] %s: (%d,%d)->(%d,%d) | Eval: %.0f | Depth: %d | Nodes: %d | Time: %.2fs %s",
                    MODE, mCount, turn, fx, fy, tx, ty, bestScore, finalDepth, nodeCount, elapsed, tag)
            end
            history[#history+1] = logStr
            print(logStr) 
            pState=g 
        else 
            mCount=mCount+1 
            history[#history+1]=string.format("[Move %d] %s: MATE/STALEMATE",mCount,turn) 
            print("[BOT] No move for "..turn)
            pState=g 
        end 
    end 

    local isSearching = false
    local function playSafe(btn)
        if isSearching then return end
        isSearching = true
        if btn then btn.Text = "THINKING..." end
        local ok, err = pcall(play)
        isSearching = false
        if btn then btn.Text = string.upper(turn).." [R]" end
        if not ok then print("[BOT] ERROR:", err) end
    end

    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    if CG:FindFirstChild("BotUI") then CG.BotUI:Destroy() end 
    if CG:FindFirstChild("BotSplash") then CG.BotSplash:Destroy() end 
    if LP and LP:FindFirstChild("PlayerGui") then
        if LP.PlayerGui:FindFirstChild("BotUI") then LP.PlayerGui.BotUI:Destroy() end
        if LP.PlayerGui:FindFirstChild("BotSplash") then LP.PlayerGui.BotSplash:Destroy() end
    end

    local sg=Instance.new("ScreenGui") 
    sg.Name="BotUI" 
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 9999
    sg.Parent=CG 

    local frame=Instance.new("Frame") 
    frame.Size=UDim2.new(0,200,0,170) 
    frame.Position=UDim2.new(0.5,-100,0.5,-85) 
    frame.BackgroundColor3=Color3.fromRGB(30,30,30) 
    frame.BorderSizePixel=2
    frame.BorderColor3=Color3.fromRGB(0,255,0)
    frame.Active=true 
    frame.Draggable=true 
    frame.Parent=sg 
    
    local cnr=Instance.new("UICorner") 
    cnr.CornerRadius=UDim.new(0,6) 
    cnr.Parent=frame 
    
    local btnTurn=Instance.new("TextButton") 
    btnTurn.Size=UDim2.new(0,180,0,32) 
    btnTurn.Position=UDim2.new(0,10,0,10) 
    btnTurn.BackgroundColor3=Color3.fromRGB(217,215,201) 
    btnTurn.TextColor3=Color3.new(0,0,0) 
    btnTurn.Text="WHITE [R]" 
    btnTurn.Font=Enum.Font.SourceSansBold 
    btnTurn.TextSize=16 
    btnTurn.BorderSizePixel=0 
    btnTurn.Parent=frame 
    local c2=Instance.new("UICorner") c2.CornerRadius=UDim.new(0,4) c2.Parent=btnTurn 
    
    local btnLog=Instance.new("TextButton") 
    btnLog.Size=UDim2.new(0,180,0,32) 
    btnLog.Position=UDim2.new(0,10,0,52) 
    btnLog.BackgroundColor3=Color3.fromRGB(80,80,80) 
    btnLog.TextColor3=Color3.new(1,1,1) 
    btnLog.Text="LOG" 
    btnLog.Font=Enum.Font.SourceSansBold 
    btnLog.TextSize=16 
    btnLog.BorderSizePixel=0 
    btnLog.Parent=frame 
    local c3=Instance.new("UICorner") c3.CornerRadius=UDim.new(0,4) c3.Parent=btnLog 
    
    local btnMode=Instance.new("TextButton") 
    btnMode.Size=UDim2.new(0,180,0,28) 
    btnMode.Position=UDim2.new(0,10,0,94) 
    btnMode.BackgroundColor3=MODES[modeIdx].color 
    btnMode.TextColor3=Color3.new(1,1,1) 
    btnMode.Text="MODE: " .. MODE 
    btnMode.Font=Enum.Font.SourceSansBold 
    btnMode.TextSize=14 
    btnMode.BorderSizePixel=0 
    btnMode.Parent=frame 
    local c4=Instance.new("UICorner") c4.CornerRadius=UDim.new(0,4) c4.Parent=btnMode 

    local btnHelp=Instance.new("TextButton") 
    btnHelp.Size=UDim2.new(0,180,0,28) 
    btnHelp.Position=UDim2.new(0,10,0,130) 
    btnHelp.BackgroundColor3=Color3.fromRGB(40, 80, 120) 
    btnHelp.TextColor3=Color3.new(1,1,1) 
    btnHelp.Text="HELP / MODE GUIDE" 
    btnHelp.Font=Enum.Font.SourceSansBold 
    btnHelp.TextSize=14 
    btnHelp.BorderSizePixel=0 
    btnHelp.Parent=frame 
    local c5=Instance.new("UICorner") c5.CornerRadius=UDim.new(0,4) c5.Parent=btnHelp 

    local helpFrame = Instance.new("ScrollingFrame")
    helpFrame.Size = UDim2.new(0, 400, 0, 400)
    helpFrame.Position = UDim2.new(0.5, -200, 0.5, -200)
    helpFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    helpFrame.BorderSizePixel = 0
    helpFrame.Visible = false
    helpFrame.ScrollBarThickness = 6
    helpFrame.Parent = sg

    local helpCorner = Instance.new("UICorner")
    helpCorner.CornerRadius = UDim.new(0, 6)
    helpCorner.Parent = helpFrame

    local helpText = Instance.new("TextLabel")
    helpText.Size = UDim2.new(1, -20, 0, 800)
    helpText.Position = UDim2.new(0, 10, 0, 10)
    helpText.BackgroundTransparency = 1
    helpText.TextColor3 = Color3.new(1, 1, 1)
    helpText.TextXAlignment = Enum.TextXAlignment.Left
    helpText.TextYAlignment = Enum.TextYAlignment.Top
    helpText.TextWrapped = true
    helpText.Font = Enum.Font.SourceSans
    helpText.TextSize = 15
    helpText.Parent = helpFrame
    
    helpText.Text = [[
MODE GUIDE:

[BALANCED]
The all-rounder. Time limit: 3.0s.
Uses a standard evaluation (material + position).
Finds good tactical moves without taking unnecessary risks.
Best for: Normal everyday games.

[MATE]
The Berserker. Time limit: 4.5s.
Heavily prioritizes attacking the enemy King.
Will sacrifice pieces if it means opening lines for a checkmate.
Weakness: Can lose on material if the attack fails.
Best for: Crushing beginners.

[GENOCIDE]
The Sadist. Time limit: 5.0s.
Refuses to deliver checkmate while ANY enemy piece is alive.
Will hunt down and destroy every pawn, knight, and rook first.
Best for: Humiliating the opponent.

[ADAPTIVE]
The Deep Thinker. Time limit: 60.0s.
Can search up to 25 plies deep.
Early stops only when the best move is stable across depths.
Will use the full 60s in complex tactical positions.
Best for: Hardcore analysis and playing at maximum strength.

[SOLID]
The Grandmaster. Time limit: 4.0s.
Values its own pieces 20% higher than normal.
Extremely strict King safety (penalizes moving King out of cover).
Will NEVER take risky piece sacrifices.
Best for: Flawless, defensive, error-free chess.

(Click outside this box to close)
]]

    local helpBg = Instance.new("TextButton")
    helpBg.Size = UDim2.new(1, 0, 1, 0)
    helpBg.BackgroundTransparency = 1
    helpBg.Text = ""
    helpBg.Parent = helpFrame

    helpBg.MouseButton1Click:Connect(function()
        helpFrame.Visible = false
    end)

    btnHelp.MouseButton1Click:Connect(function()
        helpFrame.Visible = not helpFrame.Visible
    end)

    btnMode.MouseButton1Click:Connect(function() 
        modeIdx = modeIdx % #MODES + 1
        MODE = MODES[modeIdx].name
        TIME_BUDGET = MODES[modeIdx].time
        btnMode.Text = "MODE: " .. MODE
        btnMode.BackgroundColor3 = MODES[modeIdx].color
        LINES = {}; LINES_COUNT = 0
        TT = {}
        print(string.format("[BOT] Switched to %s (time=%.1fs)", MODE, TIME_BUDGET))
    end) 

    UIS.InputBegan:Connect(function(i,gpe) 
        if not gpe and i.KeyCode==Enum.KeyCode.R then playSafe(btnTurn) end 
    end) 

    btnTurn.MouseButton1Click:Connect(function() 
        turn=(turn=="WHITE") and "BLACK" or "WHITE" 
        btnTurn.Text=string.upper(turn).." [R]" 
        btnTurn.BackgroundColor3=(turn=="WHITE") and Color3.fromRGB(217,215,201) or Color3.fromRGB(59,71,112) 
        btnTurn.TextColor3=(turn=="WHITE") and Color3.new(0,0,0) or Color3.new(1,1,1) 
        pState={}
        playSafe(btnTurn)
    end) 

    btnLog.MouseButton1Click:Connect(function() 
        if #history==0 then btnLog.Text="EMPTY!" task.wait(1) btnLog.Text="LOG" return end 
        local txt=table.concat(history,"\n") 
        if setcl then setcl(txt) btnLog.Text="COPIED!" else print(txt) btnLog.Text="IN CONSOLE!" end 
        task.wait(1) btnLog.Text="LOG" 
    end) 

    local splash = Instance.new("ScreenGui")
    splash.Name = "BotSplash"
    splash.ResetOnSpawn = false
    splash.IgnoreGuiInset = true
    splash.DisplayOrder = 10000
    splash.Parent = CG

    local sFrame = Instance.new("Frame")
    sFrame.Size = UDim2.new(0, 500, 0, 400)
    sFrame.Position = UDim2.new(0.5, -250, 0.5, -200)
    sFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    sFrame.BorderSizePixel = 0
    sFrame.Parent = splash

    local sCorner = Instance.new("UICorner")
    sCorner.CornerRadius = UDim.new(0, 8)
    sCorner.Parent = sFrame

    local sText = Instance.new("TextLabel")
    sText.Size = UDim2.new(1, -40, 1, -100)
    sText.Position = UDim2.new(0, 20, 0, 20)
    sText.BackgroundTransparency = 1
    sText.TextColor3 = Color3.new(1, 1, 1)
    sText.TextXAlignment = Enum.TextXAlignment.Left
    sText.TextYAlignment = Enum.TextYAlignment.Top
    sText.TextWrapped = true
    sText.Font = Enum.Font.SourceSans
    sText.TextSize = 16
    sText.Text = [[WELCOME TO CHESS BOT [RELEASE]

HOW TO USE:
1. Click the "WHITE/BLACK [R]" button to select your side.
2. Press the "R" key (or click the button) to make the bot calculate and highlight its move.
3. Follow the GREEN highlight (destination) and BLUE highlight (piece to move).
4. Click "MODE" to cycle through personalities (BALANCED, MATE, GENOCIDE, ADAPTIVE, SOLID).
5. Click "HELP / MODE GUIDE" for detailed descriptions of each mode.
6. Click "LOG" to copy the move history to your clipboard.

WARNING:
Use ONLY default piece skins! Custom or non-standard colors can break the bot's piece detection logic and cause it to malfunction.

DISCLAIMER:
This bot is a HELPER. It provides suggestions and tactical moves, but cannot replace human intelligence or game sense. Use it to assist your gameplay and learn chess, not to fully automate it. Play fair and have fun!

Click anywhere on this box to close.
]]
    sText.Parent = sFrame

    local sBg = Instance.new("TextButton")
    sBg.Size = UDim2.new(1, 0, 1, 0)
    sBg.BackgroundTransparency = 1
    sBg.Text = ""
    sBg.ZIndex = 10
    sBg.Parent = sFrame

    sBg.MouseButton1Click:Connect(function()
        splash:Destroy()
        task.spawn(function()
            playSafe(btnTurn)
        end)
    end)
end)
