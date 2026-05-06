local name, addon = ...;
local date = date;


--[[----------------------------------------------------------------------------
	Segment Class - Stores stat allocations
------------------------------------------------------------------------------]]
local Segment = {};



--[[----------------------------------------------------------------------------
	Helper Functions
------------------------------------------------------------------------------]]
local function getStatTable()
	local t = {};
	t.heal = 0;      -- +Healing (SP) accumulator
	t.crit = 0;      -- Spell Crit accumulator
	t.int = 0;       -- Intellect accumulator
	t.mp5 = 0;       -- MP5 accumulator
	t.spirit = 0;    -- Spirit accumulator (Druid/Priest only)
	t.spirit_sp = 0; -- Spirit throughput accumulator (Holy Priest only)
	return t;
end

--shallow table copy
local copy = addon.Util.CopyTable;



--[[----------------------------------------------------------------------------
	Segment.Create - Create a new Segment object with the given id/name
------------------------------------------------------------------------------]]
function Segment.Create(id)
	local self = copy(Segment);
	self.t = getStatTable();
	self.id = id;
	self.nameSet = false;
	self.totalHealing = 0;
	self.fillerHealing = 0;
	self.fillerCasts = 0;
	self.fillerHealingReduced = 0;
	self.fillerManaSpent = 0;
	self.totalDuration = 0;
	self.manaRestore = 0;
	self.totalManaSpent = 0;
	self.totalEffectiveHeal = 0;
	self.innervateCasts = 0;
	self.startTime = GetTime();
	self.startTimeStamp = date("%b %d, %I:%M %p");
	self.debug = {};
	self.casts = {};
	self.buckets = {};
	self.instance = {};
	self.instance.id = -1;
	self.instance.name = "";
	self.instance.level = -1;
	self.instance.difficultyId = -1;
	self.instance.bossFight = false;
	return self;
end



--[[----------------------------------------------------------------------------
	GetHPM - Healing per mana estimate for the current segment
------------------------------------------------------------------------------]]
function Segment:GetHPM()
	if self.totalManaSpent == 0 then
		return 0;
	end
	return self.totalEffectiveHeal / self.totalManaSpent;
end



--[[----------------------------------------------------------------------------
	AllocateHeal - increment per-heal stat accumulators
	  heal      : +Healing derivative for this event
	  crit      : Crit derivative for this event
	  int       : Int-via-crit derivative for this event (0 on HoT events for Druid)
	  spirit_sp : Spirit throughput derivative (Holy Priest only; 0 for all others)
	  spellId   : optional, used for debug tracking
------------------------------------------------------------------------------]]
function Segment:AllocateHeal(heal, crit, int, spirit_sp, spellId)
	self.t.heal      = self.t.heal      + heal;
	self.t.crit      = self.t.crit      + crit;
	self.t.int       = self.t.int       + int;
	self.t.spirit_sp = self.t.spirit_sp + spirit_sp;

	if HSW_ENABLE_FOR_TESTING and spellId then
		self.debug[spellId] = self.debug[spellId] and self.debug[spellId] + heal or heal;
	end
end



--[[----------------------------------------------------------------------------
	AllocateMP5 - compute and store MP5 effective-healing weight at segment end.
	  ply_mp5 terms cancel: result = (duration/5) * HPM
	  = "effective healing from 1 point of MP5 over this fight"
------------------------------------------------------------------------------]]
function Segment:AllocateMP5()
	self.t.mp5 = (self.totalDuration / 5) * self:GetHPM();
end



--[[----------------------------------------------------------------------------
	AllocateSpirit - store Spirit weight at segment end; called by parser OnSegmentEnd.
	  spiritValue : pre-computed combined Spirit weight (regen + throughput paths)
------------------------------------------------------------------------------]]
function Segment:AllocateSpirit(spiritValue)
	self.t.spirit = self.t.spirit + spiritValue;
end



--[[----------------------------------------------------------------------------
	GetDuration - get the length of this segment in seconds
------------------------------------------------------------------------------]]
function Segment:GetDuration()
	local d = self.totalDuration;
	if ( self.startTime >= 0 ) then
		d = d + (GetTime() - self.startTime);
	end
	return d;
end



--[[----------------------------------------------------------------------------
	End - the segment is no longer live, duration is fixed.
	  Injects spec-agnostic Int (mana-path) and MP5 weights, then dispatches
	  the spec-specific Spirit computation via parser:OnSegmentEnd().
------------------------------------------------------------------------------]]
function Segment:End()
	self:SnapshotTalentsAndEquipment();

	self.totalDuration = self.totalDuration + (GetTime() - self.startTime);
	self.startTime = -1;

	-- Int mana-path: additive on top of per-heal Int-via-crit from AllocateHeal
	if addon.ply_int and addon.ply_int > 0 then
		local manaFromInt = math.min(20, addon.ply_int) + 15 * math.max(0, addon.ply_int - 20);
		self.t.int = self.t.int + (manaFromInt * self:GetHPM()) / addon.ply_int;
	end

	-- MP5
	self:AllocateMP5();

	-- Spirit: spec-specific, owned by each parser
	local parser = addon.GetCurrentParser and addon:GetCurrentParser();
	if parser and parser.OnSegmentEnd then
		parser:OnSegmentEnd(self);
	end
end



--[[----------------------------------------------------------------------------
	SnapshotTalentsAndEquipment
------------------------------------------------------------------------------]]
local function FetchItemInfoFromSlot(t,id)
	if ( id and tonumber(id) ) then
		local link = GetInventoryItemLink("player",id);
		if ( link ) then
			local name,_,_,ilvl,_,_,_,_,_,icon = GetItemInfo(link);

			if ( ilvl and icon and name ) then
				t[id] = {
					link=link,
					name=name,
					ilvl=ilvl,
					icon=icon
				};
			end
		end
	end
end

function Segment:SnapshotTalentsAndEquipment()
	self.talentsSnapshot = true;
	self.selectedTalents = {};
	local r,c;
	local specGroupIndex = 1;

	for r=1,MAX_TALENT_TIERS,1 do
		for c=1,NUM_TALENT_COLUMNS,1 do
			local _, _, _, selected, _, spellID = GetTalentInfo(r,c,specGroupIndex);
			if ( selected ) then
				table.insert(self.selectedTalents,spellID);
			end
		end
	end

	self.gear = self.gear or {};
	FetchItemInfoFromSlot(self.gear,13);
	FetchItemInfoFromSlot(self.gear,14);
end



--[[----------------------------------------------------------------------------
	Increment functions
------------------------------------------------------------------------------]]
function Segment:IncTotalHealing(amount)
	self.totalHealing = self.totalHealing + amount;
	self.totalEffectiveHeal = self.totalEffectiveHeal + amount;
end

function Segment:IncFillerHealing(amount)
	self.fillerHealing = self.fillerHealing + amount;
end

function Segment:IncFillerCasts(manaCost)
	self.fillerCasts = self.fillerCasts + 1;
	self.fillerManaSpent = self.fillerManaSpent + manaCost;
end

function Segment:IncManaRestore(amount)
	self.manaRestore = self.manaRestore + amount;
end



--[[----------------------------------------------------------------------------
	Auxiliary data (Buckets)
------------------------------------------------------------------------------]]
function Segment:IncBucket(key,amount)
	if not self.buckets[key] then
		self.buckets[key] = 0;
	end
	self.buckets[key] = self.buckets[key]+amount;
end

function Segment:IncChainSpellCast(key)
	if not self.casts[key] then
		self.casts[key] = 1;
	else
		self.casts[key] = self.casts[key] + 1;
	end
end

function Segment:GetBucketInfo(key)
	local casts = self.casts[key] or 0;
	local bucket_avg = casts>0 and self.buckets[key] and (self.buckets[key]/casts) or 0;
	return casts, 0, bucket_avg;
end



--[[----------------------------------------------------------------------------
	SetupInstanceInfo - information about the instance this segment uses
------------------------------------------------------------------------------]]
function Segment:SetupInstanceInfo(isBossFight)
	local map_level, _, _ = C_ChallengeMode.GetActiveKeystoneInfo();
	local map_id = C_ChallengeMode.GetActiveChallengeMapID();
	local map_name = map_id and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(map_id) or "";
	local _,_,id = GetInstanceInfo();

	self.instance.id = map_id;
	self.instance.name = map_name;
	self.instance.level = map_level;
	self.instance.difficultyId = id;
	self.instance.bossFight = isBossFight;
end

function Segment:GetInstanceInfo()
	return self.instance;
end

--[[----------------------------------------------------------------------------
	MergeSegment - merge information from another segment into this one.
				 - only call this after both segments have Ended with segment:End()
------------------------------------------------------------------------------]]
function Segment:MergeSegmentHelper(other,tableKey)
	local keys = {};
	for k,v in pairs(self[tableKey]) do
		if type(v) == "number" then
			keys[k] = true;
		end
	end
	for k,v in pairs(other[tableKey]) do
		if type(v) == "number" then
			keys[k] = true;
		end
	end
	for k,_ in pairs(keys) do
		self[tableKey][k] = (self[tableKey][k] or 0) + (other[tableKey][k] or 0);
	end
end

function Segment:MergeSegment(other)
	local skip = {
		["totalDuration"]=true,
		["startTime"]=true,
		["startTimeStamp"]=true,
		["gear"] = true
	}

	self:MergeSegmentHelper(other,"t");
	self:MergeSegmentHelper(other,"casts");
	self:MergeSegmentHelper(other,"buckets");

	for k,v in pairs(self) do
		if ( type(v) == "number" and not skip[k] ) then
			self[k] = self[k] + (other[k] or 0.0);
		end
	end

	self.totalDuration = self.totalDuration + other:GetDuration();
end



--[[----------------------------------------------------------------------------
	Debug - print internal values of this segment to chat
------------------------------------------------------------------------------]]
function Segment:Debug()
	local tbl_header = function() print("=======") end;
	print("StatTable");
	tbl_header();
	for k,v in pairs(self.t) do
		if ( type(v) ~= "function" and type(v) ~= "table" ) then
			print(string.format("t.%s = %.5f", k, v));
		end
	end

	print("InstanceInfo");
	tbl_header();
	for k,v in pairs(self.instance) do
		if ( type(v) ~= "function" and type(v) ~= "table" ) then
			print("instance."..tostring(k),"=",v);
		end
	end

	print("Metadata");
	tbl_header();
	for k,v in pairs(self) do
		if ( type(v) ~= "function" and type(v) ~= "table" ) then
			if (type(v) == "number") then
				print(string.format("%s = %.5f", k, v));
			else
				print(k,"=",v);
			end
		end
	end

	print("Heal SpellID Buckets");
	tbl_header();
	local healMainSum = 0;
	for k,v in pairs(self.debug) do
		print(string.format("%s = %.5f", k, v));
		healMainSum = healMainSum + v;
	end

	print("Calculated Values");
	tbl_header();
	local hpm = self:GetHPM();
	local duration = self:GetDuration();
	print("hpm =",hpm);
	print(string.format("duration = %.5f",duration));
end

addon.Segment = Segment;
