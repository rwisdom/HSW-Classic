local name, addon = ...;
addon.inCombat=false;
addon.currentSegment=0;



--[[----------------------------------------------------------------------------
	Combat Start
------------------------------------------------------------------------------]]
function addon.hsw:PLAYER_REGEN_DISABLED()
	addon:StartFight(nil);
end



--[[----------------------------------------------------------------------------
	Combat End
------------------------------------------------------------------------------]]
function addon.hsw:PLAYER_REGEN_ENABLED()
	if not addon.inBossFight then
		addon:EndFight();
	end
end



--[[----------------------------------------------------------------------------
	Encounter start
------------------------------------------------------------------------------]]
function addon.hsw:ENCOUNTER_START(eventName,encounterId,encounterName)
	addon:StartFight(encounterName);
	addon.inBossFight = true; --wait til encounter_end to stop segment
end



--[[----------------------------------------------------------------------------
	Encounter end
------------------------------------------------------------------------------]]
function addon.hsw:ENCOUNTER_END()
	addon.inBossFight = false;
	addon:EndFight();
end



--[[----------------------------------------------------------------------------
	PLAYER_SPECIALIZATION_CHANGED
------------------------------------------------------------------------------]]
function addon.hsw:PLAYER_SPECIALIZATION_CHANGED()
	addon:AdjustVisibility();
end



--[[----------------------------------------------------------------------------
	PLAYER_ENTERING_WORLD
------------------------------------------------------------------------------]]
function addon.hsw:PLAYER_ENTERING_WORLD()
	addon:SetupConversionFactors();
	addon:SetupFrame();
	addon:AdjustVisibility();
	addon:TryAddTotalInstanceSegmentToHistory();
end



--[[----------------------------------------------------------------------------
	UNIT_STATS_UPDATE
------------------------------------------------------------------------------]]
function addon.hsw:UNIT_STATS_UPDATE()
	addon:UpdatePlayerStats();
end



--[[----------------------------------------------------------------------------
	PLAYER_EQUIPMENT_CHANGED
------------------------------------------------------------------------------]]
function addon.hsw:PLAYER_EQUIPMENT_CHANGED()
	addon:UpdatePlayerStats();
end



--[[----------------------------------------------------------------------------
	GROUP_ROSTER_UPDATE
------------------------------------------------------------------------------]]
function addon.hsw:GROUP_ROSTER_UPDATE()
	if ( addon.inCombat ) then --update unitmanager if someone leaves/joins group midcombat.
		addon.UnitManager:Cache();
	end
end



--[[----------------------------------------------------------------------------
	COMBAT_LOG_EVENT_UNFILTERED
------------------------------------------------------------------------------]]
local summons = {};

function addon.hsw:COMBAT_LOG_EVENT_UNFILTERED(...)
	if ( addon.inCombat ) then
		local ts,ev,_,sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID,_, _, amount, overhealing, absorbed, critFlag, arg19, arg20, arg21, arg22 = CombatLogGetCurrentEventInfo();

		if ( sourceGUID == UnitGUID("Player") ) then
			if ( ev == "SPELL_CAST_SUCCESS" ) then
				-- Innervate self-cast: increment segment counter for Spirit calculation
				if spellID == 29166 and destGUID == UnitGUID("Player") then
					local seg = addon.SegmentManager:Get(0);
					if seg then seg.innervateCasts = (seg.innervateCasts or 0) + 1; end
				end

				-- totalManaSpent tracking for HPM calculation
				local spellInfo = addon.Spells[spellID];
				if spellInfo and spellInfo.manaCost and spellInfo.manaCost > 0 then
					local seg = addon.SegmentManager:Get(0);
					if seg then
						local cost = spellInfo.manaCost;
						if addon.innerFocusActive then
							cost = 0;
							addon.innerFocusActive = false;
						end
						seg.totalManaSpent = seg.totalManaSpent + cost;
					end
				end

				-- Inner Focus: flag next healing cast as zero-mana
				if spellID == 14751 then
					addon.innerFocusActive = true;
				end
			end

			--track summons (totems) spawned
			if ( ev == "SPELL_SUMMON" ) then
				summons[destGUID] = true;
			end
		end

		--Redirect events to the stat parser
		if ( ev == "SPELL_PERIODIC_DAMAGE" or ev == "SPELL_DAMAGE" ) then
			local segment = addon.SegmentManager:Get(0);--set current segment name (if not already set)
			if ( not segment.nameSet ) then
				local dest_str = string.lower(destGUID);
				local src_str = string.lower(sourceGUID);

				local is_src_ply_or_pet = src_str:find("player") or src_str:find("pet");
				local is_dest_ply_or_pet = dest_str:find("player") or dest_str:find("pet");

				if ( is_src_ply_or_pet and not is_dest_ply_or_pet ) then
					addon.SegmentManager:SetCurrentId(destName);
				elseif ( is_dest_ply_or_pet and not is_src_ply_or_pet ) then
					addon.SegmentManager:SetCurrentId(sourceName);
				end
			end
		elseif ( ev == "SPELL_HEAL" or ev == "SPELL_PERIODIC_HEAL"  ) then
			if ( (sourceGUID == UnitGUID("Player") ) or summons[sourceGUID] ) then
				addon.StatParser:DecompHealingForCurrentSpec(ev,destGUID,spellID,critFlag,amount-overhealing,overhealing);
			end
		end
	end
end



--[[----------------------------------------------------------------------------
	Unit Events
------------------------------------------------------------------------------]]
local function UnitEventHandler(_,e,...)
	if ( e == "UNIT_AURA" ) then
		addon.BuffTracker:UpdatePlayerBuffs();
	elseif ( e == "UNIT_STATS") then
		addon:UpdatePlayerStats();
	elseif ( e == "UNIT_SPELLCAST_START" ) then
		addon.CastTracker:StartCast(...);
	elseif ( e == "UNIT_SPELLCAST_SUCCEEDED" ) then
		addon.CastTracker:FinishCast(...);
	end
end



function addon:SetupUnitEvents()
	self.frame:RegisterUnitEvent("UNIT_AURA","Player");
	self.frame:RegisterUnitEvent("UNIT_STATS","Player");
	self.frame:RegisterUnitEvent("UNIT_SPELLCAST_START","Player");
	self.frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","Player");
	self.frame:SetScript("OnEvent",UnitEventHandler);
end



--[[----------------------------------------------------------------------------
	Events
------------------------------------------------------------------------------]]
addon.hsw:RegisterEvent("PLAYER_REGEN_DISABLED");
addon.hsw:RegisterEvent("PLAYER_REGEN_ENABLED");
addon.hsw:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
addon.hsw:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED");
addon.hsw:RegisterEvent("PLAYER_ENTERING_WORLD");
addon.hsw:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
addon.hsw:RegisterEvent("ENCOUNTER_START");
addon.hsw:RegisterEvent("ENCOUNTER_END");
addon.hsw:RegisterEvent("UNIT_STATS_UPDATE");
addon.hsw:RegisterEvent("GROUP_ROSTER_UPDATE");
