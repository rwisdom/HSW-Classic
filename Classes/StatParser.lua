local name, addon = ...;



--[[----------------------------------------------------------------------------
	Classic stat constants — no rating system; these are fixed values.
------------------------------------------------------------------------------]]
addon.CritBonus = 0.5;   -- vanilla crit = 150%; bonus fraction above normal = 0.5
addon.HealConv  = 1.0;



--[[----------------------------------------------------------------------------
	SetupConversionFactors - called on PLAYER_LOGIN from Events.lua.
	Classic has no per-level rating tables; only stub legacy references used in
	unrewritten parser files (cleaned up in Phase 5).
------------------------------------------------------------------------------]]
function addon:SetupConversionFactors()
	addon.CritConv    = 1.0;  -- stub; referenced by Core.lua and DisplayPanel.lua until Phase 6/7
	addon.MasteryConv = 1.0;  -- stub; referenced by old parsers until Phase 5 rewrites
end



--[[----------------------------------------------------------------------------
	UpdatePlayerStats - Update stats for current player.
------------------------------------------------------------------------------]]
function addon:UpdatePlayerStats()
	self.ply_sp  = GetSpellBonusHealing();
	self.ply_crt = GetSpellCritChance(2) / 100;  -- Holy school index 2
	local ib, ip, in_ = UnitStat("player", 4);
	self.ply_int = ib + ip + in_;
	self.ply_mp5 = select(2, GetManaRegen()) * 5;
	local sb, sp, sn = UnitStat("player", 5);
	self.ply_spi = sb + sp + sn;
end



--[[----------------------------------------------------------------------------
	Basic Stat Derivative Calculations
------------------------------------------------------------------------------]]
-- Int-via-crit: spec-specific; base = 0; parsers override via f.Intellect
local function _Intellect(ev, s, heal, destUnit, f)
	if ( f and f.Intellect ) then
		return f.Intellect(ev, s, heal, destUnit);
	end
	return 0;
end

-- Crit
local function _CriticalStrike(ev, s, heal, destUnit, f)
	if ( f and f.CriticalStrike ) then
		return f.CriticalStrike(ev, s, heal, destUnit);
	end
	local C = math.min(addon.ply_crt, 1.0);
	return heal * addon.CritBonus / (1 + C * addon.CritBonus);
end

-- Spirit throughput (Holy Priest Spiritual Guidance path); base = 0
local function _SpiritSP(ev, s, heal, destUnit, f)
	if ( f and f.SpiritSP ) then
		return f.SpiritSP(ev, s, heal, destUnit);
	end
	return 0;
end

local BaseParsers = {
	Intellect      = _Intellect,
	CriticalStrike = _CriticalStrike,
	SpiritSP       = _SpiritSP,
}



--[[----------------------------------------------------------------------------
	StatParser - Create & Get combat log parsers for each spec
------------------------------------------------------------------------------]]
local StatParser = {};



--[[----------------------------------------------------------------------------
	Create - add a new stat parser to be used by the addon.
------------------------------------------------------------------------------]]
function StatParser:Create(id, func_I, func_C, func_SS, func_HealEvent, func_DamageEvent)
	self[id] = {};
	if ( func_HealEvent )  then self[id].HealEvent     = func_HealEvent;  end
	if ( func_DamageEvent) then self[id].DamageEvent   = func_DamageEvent; end
	if ( func_I )          then self[id].Intellect     = func_I;           end
	if ( func_C )          then self[id].CriticalStrike = func_C;          end
	if ( func_SS )         then self[id].SpiritSP      = func_SS;          end
end


--[[----------------------------------------------------------------------------
	GetParserForCurrentSpec
------------------------------------------------------------------------------]]
function StatParser:GetParserForCurrentSpec()
    local i = GetSpecialization();
	local specId = GetSpecializationInfo(i);
	return self[specId and tonumber(specId) or 0], specId;
end

function StatParser:IncFillerHealing(heal)
	local cur_seg = addon.SegmentManager:Get(0);
	local ttl_seg = addon.SegmentManager:Get("Total");
	if ( cur_seg ) then
		cur_seg:IncFillerHealing(heal);
	end
	if ( ttl_seg ) then
		ttl_seg:IncFillerHealing(heal);
	end
end

function StatParser:IncBucket(key, amount)
	local cur_seg = addon.SegmentManager:Get(0);
	local ttl_seg = addon.SegmentManager:Get("Total");
	if ( cur_seg ) then
		cur_seg:IncBucket(key, amount);
	end
	if ( ttl_seg ) then
		ttl_seg:IncBucket(key, amount);
	end
end

function StatParser:IncChainSpellCast(spellID)
	local cur_seg = addon.SegmentManager:Get(0);
	local ttl_seg = addon.SegmentManager:Get("Total");
	if ( cur_seg ) then
		cur_seg:IncChainSpellCast(spellID);
	end
	if ( ttl_seg ) then
		ttl_seg:IncChainSpellCast(spellID);
	end
end

function StatParser:IncHealing(heal, updateFiller, updateTotal)
	local cur_seg = addon.SegmentManager:Get(0);
	local ttl_seg = addon.SegmentManager:Get("Total");
	if ( cur_seg ) then
		if ( updateFiller ) then
			cur_seg:IncFillerHealing(heal);
		end
		if ( updateTotal ) then
			cur_seg:IncTotalHealing(heal);
		end
	end
	if ( ttl_seg ) then
		if ( updateFiller ) then
			ttl_seg:IncFillerHealing(heal);
		end
		if ( updateTotal ) then
			ttl_seg:IncTotalHealing(heal);
		end
	end
end

function StatParser:Allocate(ev, spellInfo, heal, critical, destUnit, f)
	local cur_seg = addon.SegmentManager:Get(0);
	local ttl_seg = addon.SegmentManager:Get("Total");

	if ( HSW_ENABLE_FOR_TESTING ) then
		addon:Msg("allocate spellid="..(spellInfo.spellID or "unknown").." destunit="..destUnit.." amount="..heal);
	end

	if addon.ply_sp == 0 then return end

	-- normalise crits: strip bonus so crit/non-crit heals produce identical derivatives
	if critical then heal = heal / (1 + addon.CritBonus) end

	local _SP = heal / addon.ply_sp;
	local _C  = _CriticalStrike(ev, spellInfo, heal, destUnit, f);
	local _I  = _Intellect(ev, spellInfo, heal, destUnit, f);
	local _SS = _SpiritSP(ev, spellInfo, heal, destUnit, f);

	if ( cur_seg ) then
		cur_seg:AllocateHeal(_SP, _C, _I, _SS, spellInfo.spellID);
	end
	if ( ttl_seg ) then
		ttl_seg:AllocateHeal(_SP, _C, _I, _SS, spellInfo.spellID);
	end

	addon:UpdateDisplayStats();
end



--[[----------------------------------------------------------------------------
	DecompHealingForCurrentSpec
------------------------------------------------------------------------------]]
function StatParser:DecompHealingForCurrentSpec(ev, destGUID, spellID, critFlag, heal, overhealing)
	local f, specId = self:GetParserForCurrentSpec();

	if ( f ) then
		local spellInfo = addon.Spells:Get(spellID);
		if ( spellInfo and (spellInfo.spellType == specId or spellInfo.spellType == addon.SpellType.SHARED) ) then
			local destUnit = addon.UnitManager:Find(destGUID);
			if destUnit then

				local skipAllocate = false;
				if ( f.HealEvent ) then
					skipAllocate = f.HealEvent(ev, spellInfo, heal, overhealing, destUnit, f, heal);
				end

				if ( addon.hsw.db.global.excludeRaidHealingCooldowns and spellInfo.cd ) then
					return;
				end

				self:IncHealing(heal, spellInfo.filler, true);

				if ( not skipAllocate ) then
					self:Allocate(ev, spellInfo, heal, critFlag, destUnit, f);
				end
			end
		elseif ( not spellInfo ) then
			addon:DiscoverIgnoredSpell(spellID);
		end
	end
end



--[[----------------------------------------------------------------------------
	DecompDamageDone
------------------------------------------------------------------------------]]
function StatParser:DecompDamageDone(amt, spellID, critFlag)
	local f, specId = self:GetParserForCurrentSpec();

	local spellInfo = addon.Spells:Get(spellID);
	if ( spellInfo and (spellInfo.spellType == specId or spellInfo.spellType == addon.SpellType.SHARED) ) then
		if ( f and f.DamageEvent ) then
			f.DamageEvent(spellInfo, amt, critFlag);
		end
	end
end



--[[----------------------------------------------------------------------------
	DecompDamageTaken — removed (Versatility DR path; no Versatility in Classic).
	Stub retained to avoid nil-call errors until Phase 3 cleans up Events.lua.
------------------------------------------------------------------------------]]
function StatParser:DecompDamageTaken(amt, dontClamp) end



--[[----------------------------------------------------------------------------
	IsCurrentSpecSupported - Check if current spec is supported
------------------------------------------------------------------------------]]
function StatParser:IsCurrentSpecSupported()
	local f = self:GetParserForCurrentSpec();
	if ( f ) then
		return true;
	else
		return false;
	end
end



addon.BaseParsers = BaseParsers;
addon.StatParser = StatParser;
