--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroLib
local HL         = HeroLib
local Cache      = HeroCache
local Unit       = HL.Unit
local Player     = Unit.Player
local Target     = Unit.Target
local Pet        = Unit.Pet
local Spell      = HL.Spell
local MultiSpell = HL.MultiSpell
local Item       = HL.Item
-- HeroRotation
local HR         = HeroRotation
local Cast       = HR.Cast
local AoEON      = HR.AoEON
local CDsON      = HR.CDsON

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- GUI Settings
local Everyone = HR.Commons.Everyone
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Hunter.Commons,
  Commons2 = HR.GUISettings.APL.Hunter.Commons2,
  Survival = HR.GUISettings.APL.Hunter.Survival
}

-- Spells
local S = Spell.Hunter.Survival

-- Items
local I = Item.Hunter.Survival
local TrinketsOnUseExcludes = {
  I.DreadfireVessel:ID(),
}

-- Legendaries
local NessingwarysTrappingEquipped = Player:HasLegendaryEquipped(67)
local SoulForgeEmbersEquipped = Player:HasLegendaryEquipped(68)
local RylakstalkersConfoundingEquipped = Player:HasLegendaryEquipped(79)
HL:RegisterForEvent(function()
  NessingwarysTrappingEquipped = Player:HasLegendaryEquipped(67)
  SoulForgeEmbersEquipped = Player:HasLegendaryEquipped(68)
  RylakstalkersConfoundingEquipped = Player:HasLegendaryEquipped(79)
end, "PLAYER_EQUIPMENT_CHANGED")

-- Rotation Var
local SummonPetSpells = { S.SummonPet, S.SummonPet2, S.SummonPet3, S.SummonPet4, S.SummonPet5 }
local Enemy8y, EnemyCount8y

-- Stuns
local StunInterrupts = {
  {S.Intimidation, "Cast Intimidation (Interrupt)", function () return true; end},
}

-- Function to see if we're going to cap focus
local function CheckFocusCap(SpellCastTime, GenFocus)
  local GeneratedFocus = GenFocus or 0
  return (Player:Focus() + Player:FocusCastRegen(SpellCastTime) + GeneratedFocus < Player:FocusMax())
end

-- CastCycle/CastTargetIf functions
-- target_if=min:remains
local function EvaluateTargetIfFilterSerpentStingRemains(TargetUnit)
  return (TargetUnit:DebuffRemains(S.SerpentStingDebuff))
end

-- target_if=min:bloodseeker.remains
local function EvaluateTargetIfFilterKillCommandRemains(TargetUnit)
  return (TargetUnit:DebuffRemains(S.BloodseekerDebuff))
end

-- target_if=max:debuff.latent_poison_injection.stack
local function EvaluateTargetIfFilterRaptorStrikeLatentStacks(TargetUnit)
  return (TargetUnit:DebuffStack(S.LatentPoisonDebuff))
end

-- if=!dot.serpent_sting.ticking&target.time_to_die>7
local function EvaluateTargetIfSerpentStingAPST(TargetUnit)
  return (TargetUnit:DebuffDown(S.SerpentStingDebuff) and TargetUnit:TimeToDie() > 7)
end

-- if=refreshable&target.time_to_die>7
local function EvaluateTargetIfSerpentStingAPST2(TargetUnit)
  return (TargetUnit:DebuffRefreshable(S.SerpentStingDebuff) and TargetUnit:TimeToDie() > 7 )
end

-- if=refreshable&talent.hydras_bite.enabled&target.time_to_die>8
local function EvaluateTargetIfSerpentStingCleave(TargetUnit)
  return (TargetUnit:DebuffRefreshable(S.SerpentStingDebuff) and S.HydrasBite:IsAvailable() and TargetUnit:TimeToDie() > 8)
end

-- if=refreshable
local function EvaluateTargetIfSerpentStingCleave2(TargetUnit)
  return (TargetUnit:DebuffRefreshable(S.SerpentStingDebuff))
end

-- if=full_recharge_time<gcd&focus+cast_regen<focus.max
local function EvaluateKillCommandCycleCondition1(TargetUnit)
  return (S.KillCommand:FullRechargeTime() < Player:GCD() and CheckFocusCap(S.KillCommand:ExecuteTime(), 15))
end

-- if=focus+cast_regen<focus.max
local function EvaluateTargetIfKillCommandAPST(TargetUnit)
  return (CheckFocusCap(S.KillCommand:ExecuteTime(), 15))
end

-- if=buff.tip_of_the_spear.stack=3|dot.shrapnel_bomb.ticking
local function EvaluateTargetIfRaptorStrikeAPST(TargetUnit)
  return (Player:BuffStack(S.TipoftheSpearBuff) == 3 or TargetUnit:DebuffUp(S.ShrapnelBombDebuff))
end

-- if=buff.mongoose_fury.up&buff.mongoose_fury.remains<focus%(action.mongoose_bite.cost-cast_regen)*gcd&!buff.wild_spirits.remains|buff.mongoose_fury.remains&next_wi_bomb.pheromone
local function EvaluateTargetIfMongoostBiteAPST(TargetUnit) 
  return (Player:BuffUp(S.MongooseFuryBuff) and Player:BuffRemains(S.MongooseFuryBuff) < Player:Focus() / (S.MongooseBite:Cost() - Player:FocusCastRegen(S.MongooseBite:ExecuteTime())) * Player:GCD() and not TargetUnit:DebuffRemains(S.WildSpiritsDebuff) or Player:BuffRemains(S.MongooseFuryBuff) and S.PheromoneBomb:IsCastable())
end

-- if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max-15|dot.shrapnel_bomb.ticking|buff.wild_spirits.remains
local function EvaluateTargetIfMongooseBiteAPST2(TargetUnit) 
  return (Player:BuffUp(S.MongooseFuryBuff) or Player:Focus() + Player:FocusCastRegen(S.MongooseBite:ExecuteTime()) > Player:FocusMax() - 15 or TargetUnit:DebuffUp(S.ShrapnelBombDebuff) or TargetUnit:DebuffRemains(S.WildSpiritsDebuff))
end

-- if=buff.vipers_venom.up&buff.vipers_venom.remains<gcd|!ticking
local function EvaluateTargetIfSerpentStingST(TargetUnit)
  return (Player:BuffUp(S.VipersVenomBuff) and Player:BuffRemains(S.VipersVenomBuff) < Player:GCD() or TargetUnit:DebuffDown(S.SerpentStingDebuff))
end

-- if=buff.tip_of_the_spear.stack=3
local function EvaluateTargetIfRaptorStrikeST(TargetUnit)
  return (Player:BuffStack(S.TipoftheSpearBuff) == 3)
end

-- if=refreshable|buff.vipers_venom.up
local function EvaluateTargetIfSerpentStingST2(TargetUnit)
  return (TargetUnit:DebuffRefreshable(S.SerpentStingDebuff) or Player:BuffUp(S.VipersVenomBuff))
end

-- if=focus+cast_regen<focus.max&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
local function EvaluateTargetIfKillCommandST(TargetUnit)
  return (CheckFocusCap(S.KillCommand:ExecuteTime(), 15) and (NessingwarysTrappingEquipped and not S.FreezingTrap:CooldownUp() and not S.TarTrap:CooldownUp() or not NessingwarysTrappingEquipped))
end

-- if=dot.shrapnel_bomb.ticking|buff.mongoose_fury.stack=5
local function EvaluateTargetIfMongooseBiteST(TargetUnit)
  return (TargetUnit:DebuffUp(S.ShrapnelBombDebuff) or Player:BuffStack(S.MongooseFuryBuff) == 5)
end

-- if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max-15|dot.shrapnel_bomb.ticking
local function EvaluateTargetIfMongooseBiteST2(TargetUnit)
  return (Player:BuffUp(S.MongooseFuryBuff) or Player:Focus() + Player:FocusCastRegen(S.KillCommand:ExecuteTime()) > Player:FocusMax() - 15 or TargetUnit:DebuffUp(S.ShrapnelBombDebuff))
end

-- if=buff.vipers_venom.remains&(buff.vipers_venom.remains<gcd|refreshable)
local function EvaluateTargetIfSerpentStingBOP(TargetUnit)
  return (Player:BuffUp(S.VipersVenomBuff) and (Player:BuffRemains(S.VipersVenomBuff) < Player:GCD() or TargetUnit:DebuffRefreshable(S.SerpentStingDebuff)))
end

-- if=focus+cast_regen<focus.max&buff.nesingwarys_trapping_apparatus.up
local function EvaluateTargetIfKillCommandBOP(TargetUnit)
  return (CheckFocusCap(S.KillCommand:ExecuteTime(), 15) and Player:BuffUp(S.NessingwarysTrappingBuff))
end

-- if=focus+cast_regen<focus.max&!runeforge.nessingwarys_trapping_apparatus.equipped|focus+cast_regen<focus.max&((runeforge.nessingwarys_trapping_apparatus.equipped&!talent.steel_trap.enabled&cooldown.freezing_trap.remains&cooldown.tar_trap.remains)|(runeforge.nessingwarys_trapping_apparatus.equipped&talent.steel_trap.enabled&cooldown.freezing_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd&cooldown.tar_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd&cooldown.steel_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd))|focus<action.mongoose_bite.cost
local function EvaluateTargetIfKillCommandBOP2(TargetUnit)
  local FocusCap = CheckFocusCap(S.KillCommand:ExecuteTime(), 15)
  local KCFCR = Player:FocusCastRegen(S.KillCommand:ExecuteTime())
  local CurFocus = Player:Focus()
  local CurGCD = Player:GCD()
  local MongooseCost = S.MongooseBite:Cost()
  return (FocusCap and not NessingwarysTrappingEquipped or FocusCap and ((NessingwarysTrappingEquipped and not S.SteelTrap:IsAvailable() and not S.FreezingTrap:CooldownUp() and not S.TarTrap:CooldownUp()) or (NessingwarysTrappingEquipped and S.SteelTrap:IsAvailable() and S.FreezingTrap:CooldownRemains() > CurFocus / (MongooseCost - KCFCR) * CurGCD and S.TarTrap:CooldownRemains() > CurFocus / (MongooseCost - KCFCR) * CurGCD and S.SteelTrap:CooldownRemains() > CurFocus / (MongooseCost - KCFCR) * CurGCD)) or CurFocus < MongooseCost)
end

-- if=buff.coordinated_assault.up&buff.coordinated_assault.remains<1.5*gcd
local function EvaluateTargetIfRaptorStrikeBOP(TargetUnit)
  return (Player:BuffUp(S.CoordinatedAssault) and Player:BuffRemains(S.CoordinatedAssault) < 1.5 * Player:GCD())
end

-- if=dot.serpent_sting.refreshable&!buff.coordinated_assault.up
local function EvaluateTargetIfSerpentStingBOP2(TargetUnit)
  return (Target:DebuffRefreshable(S.SerpentStingDebuff) and Player:BuffDown(S.CoordinatedAssault))
end

-- if=focus+cast_regen<focus.max&full_recharge_time<gcd&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
local function EvaluateTargetIfKillCommandCleave(TargetUnit)
  return (CheckFocusCap(S.KillCommand:ExecuteTime(), 15) and S.KillCommand:FullRechargeTime() < Player:GCD() and (NessingwarysTrappingEquipped and not S.FreezingTrap:CooldownUp() and not S.TarTrap:CooldownUp() or not NessingwarysTrappingEquipped))
end

-- target_if=focus+cast_regen<focus.max&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
local function EvaluateCycleKillCommandCleave(TargetUnit)
  return (CheckFocusCap(S.KillCommand:ExecuteTime(), 15) and (NessingwarysTrappingEquipped and not S.FreezingTrap:CooldownUp() and not S.TarTrap:CooldownUp() or not NessingwarysTrappingEquipped))
end

local function Precombat()
  -- flask
  -- augmentation
  -- food
  -- summon_pet
  if S.SummonPet:IsCastable() then
    if Cast(SummonPetSpells[Settings.Commons2.SummonPetSlot]) then return "summon_pet precombat 2"; end
  end
  -- snapshot_stats
  if Everyone.TargetIsValid() then
    -- Manually added: kill_shot
    -- Could be removed?
    if S.KillShot:IsReady() then
      if Cast(S.KillShot, nil, nil, not Target:IsSpellInRange(S.KillShot)) then return "kill_shot precombat 4"; end
    end
    -- tar_trap,if=runeforge.soulforge_embers
    if S.TarTrap:IsCastable() and (SoulForgeEmbersEquipped) then
      if Cast(S.TarTrap, Settings.Commons2.GCDasOffGCD.TarTrap) then return "tar_trap precombat 6"; end
    end
    -- Manually added: flare,if=runeforge.soulforge_embers&prev_gcd.1.tar_trap
    if S.Flare:IsCastable() and (SoulForgeEmbersEquipped and Player:PrevGCD(1, S.TarTrap)) then
      if Cast(S.Flare, Settings.Commons2.GCDasOffGCD.Flare) then return "flare precombat 8"; end
    end
    -- steel_trap,precast_time=20
    if S.SteelTrap:IsCastable() and Target:DebuffDown(S.SteelTrapDebuff) then
      if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap precombat 10"; end
    end
    -- Manually added: harpoon
    if S.Harpoon:IsCastable() and not Target:IsInMeleeRange(5) then
      if Cast(S.Harpoon, nil, nil, not Target:IsInRange(30)) then return "harpoon precombat 12"; end
    end
    -- Manually added: mongoose_bite or raptor_strike
    if Target:IsInMeleeRange(5) then
      if S.MongooseBite:IsReady() then
        if Cast(S.MongooseBite) then return "mongoose_bite precombat 14"; end
      elseif S.RaptorStrike:IsReady() then
        if Cast(S.RaptorStrike) then return "raptor_strike precombat 16"; end
      end
    end
  end
end

local function CDs()
  -- harpoon,if=talent.terms_of_engagement.enabled&focus<focus.max
  if S.Harpoon:IsReady() and (S.TermsofEngagement:IsAvailable() and Player:Focus() < Player:FocusMax()) then
    if Cast(S.Harpoon, nil, nil, not Target:IsInRange(30)) then return "harpoon cds 2"; end
  end
  -- use_item,name=dreadfire_vessel,if=covenant.kyrian&cooldown.resonating_arrow.remains>10|!covenant.kyrian
  if I.DreadfireVessel:IsEquippedAndReady() and (Player:Covenant() == "Kyrian" and S.ResonatingArrow:CooldownRemains() > 10 or Player:Covenant() ~= "Kyrian") then
    if Cast(I.DreadfireVessel, nil, nil, not Target:IsInRange(50)) then return "dreadfire_vessel cds 4"; end
  end
  -- blood_fury,if=cooldown.coordinated_assault.remains>30
  if S.BloodFury:IsCastable() and (S.CoordinatedAssault:CooldownRemains() > 30) then
    if Cast(S.BloodFury, Settings.Commons.OffGCDasOffGCD.Racials) then return "blood_fury cds 6"; end
  end
  -- ancestral_call,if=cooldown.coordinated_assault.remains>30
  if S.AncestralCall:IsCastable() and (S.CoordinatedAssault:CooldownRemains() > 30) then
    if Cast(S.AncestralCall, Settings.Commons.OffGCDasOffGCD.Racials) then return "ancestral_call cds 8"; end
  end
  -- fireblood,if=cooldown.coordinated_assault.remains>30
  if S.Fireblood:IsCastable() and (S.CoordinatedAssault:CooldownRemains() > 30) then
    if Cast(S.Fireblood, Settings.Commons.OffGCDasOffGCD.Racials) then return "fireblood cds 10"; end
  end
  -- lights_judgment
  if S.LightsJudgment:IsCastable() then
    if Cast(S.LightsJudgment, Settings.Commons.OffGCDasOffGCD.Racials, nil, not Target:IsInRange(40)) then return "lights_judgment cds 12"; end
  end
  -- bag_of_tricks,if=cooldown.kill_command.full_recharge_time>gcd
  if S.BagofTricks:IsCastable() and (S.KillCommand:FullRechargeTime() > Player:GCD()) then
    if Cast(S.BagofTricks, Settings.Commons.OffGCDasOffGCD.Racials, nil, not Target:IsInRange(40)) then return "bag_of_tricks cds 14"; end
  end
  -- berserking,if=cooldown.coordinated_assault.remains>60|time_to_die<13
  if S.Berserking:IsCastable() and (S.CoordinatedAssault:CooldownRemains() > 60 or Target:TimeToDie() < 13) then
    if Cast(S.Berserking, Settings.Commons.OffGCDasOffGCD.Racials) then return "berserking cds 16"; end
  end
  -- muzzle
  -- potion,if=target.time_to_die<60|buff.coordinated_assault.up
  if I.PotionOfSpectralAgility:IsReady() and (Target:TimeToDie() < 60 or Player:BuffUp(S.CoordinatedAssault)) then
    if Cast(I.PotionOfSpectralAgility, nil, Settings.Commons.DisplayStyle.Potions) then return "potion cds 18"; end
  end
  -- tar_trap,if=focus+cast_regen<focus.max&runeforge.soulforge_embers.equipped&tar_trap.remains<gcd&cooldown.flare.remains<gcd&(active_enemies>1|active_enemies=1&time_to_die>5*gcd)
  if S.TarTrap:IsCastable() and (CheckFocusCap(S.TarTrap:ExecuteTime()) and SoulForgeEmbersEquipped and Target:DebuffDown(S.SoulforgeEmbersDebuff) and (EnemyCount8y > 1 or EnemyCount8y == 1 and Target:TimeToDie() > 5 * Player:GCD())) then
    if Cast(S.TarTrap, Settings.Commons2.GCDasOffGCD.TarTrap, nil, not Target:IsInRange(40)) then return "tar_trap cds 20"; end
  end
  
  -- flare,if=focus+cast_regen<focus.max&tar_trap.up&runeforge.soulforge_embers.equipped&time_to_die>4*gcd
  if S.Flare:IsCastable() and (CheckFocusCap(S.Flare:ExecuteTime()) and SoulForgeEmbersEquipped and Target:TimeToDie() > 4 * Player:GCD()) then
    if Cast(S.Flare, Settings.Commons2.GCDasOffGCD.Flare) then return "flare cds 22"; end
  end
  -- kill_shot,if=active_enemies=1&target.time_to_die<focus%(action.mongoose_bite.cost-cast_regen)*gcd
  if S.KillShot:IsReady() and (EnemyCount8y == 1 and Target:TimeToDie() < Player:Focus() / (S.KillShot:Cost() - Player:FocusCastRegen(S.KillShot:ExecuteTime())) * Player:GCD()) then
    if Cast(S.KillShot, nil, nil, not Target:IsSpellInRange(S.KillShot)) then return "kill_shot cds 24"; end
  end
  -- mongoose_bite,if=active_enemies=1&target.time_to_die<focus%(action.mongoose_bite.cost-cast_regen)*gcd
  if S.MongooseBite:IsReady() and (EnemyCount8y == 1 and Target:TimeToDie() < Player:Focus() / (S.MongooseBite:Cost() - Player:FocusCastRegen(S.MongooseBite:ExecuteTime())) * Player:GCD()) then
    if Cast(S.MongooseBite, nil, nil, not Target:IsInMeleeRange(5)) then return "mongoose_bite cds 26"; end
  end
  -- raptor_strike,if=active_enemies=1&target.time_to_die<focus%(action.mongoose_bite.cost-cast_regen)*gcd
  if S.RaptorStrike:IsReady() and (EnemyCount8y == 1 and Target:TimeToDie() < Player:Focus() / (S.MongooseBite:Cost() - Player:FocusCastRegen(S.MongooseBite:ExecuteTime())) * Player:GCD()) then
    if Cast(S.RaptorStrike, nil, nil, not Target:IsSpellInRange(S.RaptorStrike)) then return "raptor_strike cds 28"; end
  end
  -- aspect_of_the_eagle,if=target.distance>=6
  if S.AspectoftheEagle:IsCastable() and not Target:IsInRange(6) then
    if Cast(S.AspectoftheEagle, Settings.Survival.OffGCDasOffGCD.AspectOfTheEagle) then return "aspect_of_the_eagle cds 30"; end
  end
end

local function NTA()
  -- steel_trap
  if S.SteelTrap:IsCastable() then
    if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap nta 2"; end
  end
  -- freezing_trap,if=!buff.wild_spirits.remains|buff.wild_spirits.remains&cooldown.kill_command.remains&focus<action.mongoose_bite.cost
  if S.FreezingTrap:IsCastable() and (Target:DebuffDown(S.WildSpiritsDebuff) or Target:DebuffUp(S.WildSpiritsDebuff) and not S.KillCommand:CooldownUp() and Player:Focus() < S.MongooseBite:Cost()) then
    if Cast(S.FreezingTrap, nil, nil, not Target:IsInRange(40)) then return "freezing_trap nta 4"; end
  end
  -- tar_trap,if=!buff.wild_spirits.remains|buff.wild_spirits.remains&cooldown.kill_command.remains&focus<action.mongoose_bite.cost
  if S.TarTrap:IsCastable() and (Target:DebuffDown(S.WildSpiritsDebuff) or Target:DebuffUp(S.WildSpiritsDebuff) and not S.KillCommand:CooldownUp() and Player:Focus() < S.MongooseBite:Cost()) then
    if Cast(S.TarTrap, nil, nil, not Target:IsInRange(40)) then return "tar_trap nta 6"; end
  end
end

local function ST()
  if CDsON() then
    -- flayed_shot
    if S.FlayedShot:IsCastable() then
      if Cast(S.FlayedShot, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "flayed_shot st 2"; end
    end
    -- wild_spirits
    if S.WildSpirits:IsCastable() then
      if Cast(S.WildSpirits, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "wild_spirits st 4"; end
    end
    -- resonating_arrow
    if S.ResonatingArrow:IsCastable() then
      if Cast(S.ResonatingArrow, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "resonating_arrow st 6"; end
    end
  end
  -- serpent_sting,target_if=min:remains,if=buff.vipers_venom.up&buff.vipers_venom.remains<gcd|!ticking
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingST) then return "serpent_sting st 8"; end
  end
  -- death_chakram,if=focus+cast_regen<focus.max
  if CDsON() and S.DeathChakram:IsCastable() and (CheckFocusCap(S.DeathChakram:ExecuteTime())) then
    if Cast(S.DeathChakram, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "death_chakram st 10"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.tip_of_the_spear.stack=3
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfRaptorStrikeST) then return "raptor_strike st 12"; end
  end
  -- coordinated_assault
  if CDsON() and S.CoordinatedAssault:IsCastable() then
    if Cast(S.CoordinatedAssault, Settings.Survival.GCDasOffGCD.CoordinatedAssault) then return "coordinated_assault st 14"; end
  end
  -- kill_shot
  if S.KillShot:IsReady() then
    if Cast(S.KillShot, nil, nil, not Target:IsInRange(40)) then return "kill_shot st 16"; end
  end
  -- wildfire_bomb,if=full_recharge_time<gcd&focus+cast_regen<focus.max|(next_wi_bomb.volatile&dot.serpent_sting.ticking&dot.serpent_sting.refreshable|next_wi_bomb.pheromone&focus+cast_regen<focus.max-action.kill_command.cast_regen*3&!buff.mongoose_fury.remains)
  if S.VolatileBomb:IsCastable() and (S.WildfireBomb:FullRechargeTime() < Player:GCD() and CheckFocusCap(S.WildfireBomb:ExecuteTime()) or Target:DebuffUp(S.SerpentStingDebuff) and Target:DebuffRefreshable(S.SerpentStingDebuff)) then
    if Cast(S.VolatileBomb, nil, nil, not Target:IsInRange(40)) then return "volatile_bomb st 18"; end
  end
  if S.PheromoneBomb:IsCastable() and (S.WildfireBomb:FullRechargeTime() < Player:GCD() and CheckFocusCap(S.WildfireBomb:ExecuteTime()) or Player:Focus() + Player:FocusCastRegen(S.PheromoneBomb:ExecuteTime()) < Player:FocusMax() - Player:FocusCastRegen(S.KillCommand:ExecuteTime()) * 3 and Player:BuffDown(S.MongooseFuryBuff)) then
    if Cast(S.PheromoneBomb, nil, nil, not Target:IsInRange(40)) then return "pheromone_bomb st 20"; end
  end
  if S.ShrapnelBomb:IsCastable() and (S.WildfireBomb:FullRechargeTime() < Player:GCD() and CheckFocusCap(S.WildfireBomb:ExecuteTime())) then
    if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb st 22"; end
  end
  -- steel_trap,if=focus+cast_regen<focus.max
  if S.SteelTrap:IsCastable() and (CheckFocusCap(S.SteelTrap:ExecuteTime())) then
    if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap st 24"; end
  end
  -- flanking_strike,if=focus+cast_regen<focus.max
  if S.FlankingStrike:IsCastable() and (CheckFocusCap(S.FlankingStrike:ExecuteTime())) then
    if Cast(S.FlankingStrike, nil, nil, not Target:IsInRange(15)) then return "flanking_strike st 26"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateTargetIfKillCommandST) then return "kill_command st 28"; end
  end
  -- carve,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped
  if S.Carve:IsReady() and (EnemyCount8y > 1 and not RylakstalkersConfoundingEquipped) then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve st 30"; end
  end
  -- butchery,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped&cooldown.wildfire_bomb.full_recharge_time>spell_targets&(charges_fractional>2.5|dot.shrapnel_bomb.ticking)
  if S.Butchery:IsReady() and (EnemyCount8y > 1 and not RylakstalkersConfoundingEquipped and S.WildfireBomb:FullRechargeTime() > EnemyCount8y and (S.Butchery:ChargesFractional() > 2.5 or Target:DebuffUp(S.ShrapnelBombDebuff))) then
    if Cast(S.Butchery, nil, nil, not Target:IsInRange(8)) then return "butchery st 32"; end
  end
  -- a_murder_of_crows
  if S.AMurderofCrows:IsReady() then
    if Cast(S.AMurderofCrows, Settings.Commons.GCDasOffGCD.AMurderofCrows, nil, not Target:IsInRange(40)) then return "a_murder_of_crows st 34"; end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=dot.shrapnel_bomb.ticking|buff.mongoose_fury.stack=5
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfMongooseBiteST) then return "mongoose_bite st 36"; end
  end
  -- serpent_sting,target_if=min:remains,if=refreshable|buff.vipers_venom.up
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingST2) then return "serpent_sting st 38"; end
  end
  -- wildfire_bomb,if=next_wi_bomb.shrapnel&dot.serpent_sting.remains>5*gcd|runeforge.rylakstalkers_confounding_strikes.equipped
  if S.ShrapnelBomb:IsCastable() and (Target:DebuffRemains(S.SerpentStingDebuff) > 5 * Player:GCD() or RylakstalkersConfoundingEquipped) then
    if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb st 40"; end
  end
  -- chakrams
  if S.Chakrams:IsReady() then
    if Cast(S.Chakrams, nil, nil, not Target:IsInRange(40)) then return "chakrams st 42"; end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max-15|dot.shrapnel_bomb.ticking
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfMongooseBiteST2) then return "mongoose_bite st 44"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "raptor_strike st 46"; end
  end
  -- wildfire_bomb,if=next_wi_bomb.volatile&dot.serpent_sting.ticking|next_wi_bomb.pheromone|next_wi_bomb.shrapnel
  if S.VolatileBomb:IsCastable() and (Target:DebuffUp(S.SerpentStingDebuff)) then
    if Cast(S.VolatileBomb, nil, nil, not Target:IsInRange(40)) then return "volatile_bomb st 48"; end
  end
  if S.PheromoneBomb:IsCastable() then
    if Cast(S.PheromoneBomb, nil, nil, not Target:IsInRange(40)) then return "pheromone_bomb st 50"; end
  end
  if S.ShrapnelBomb:IsCastable() then
    if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb st 52"; end
  end
end

local function APST()
  -- death_chakram,if=focus+cast_regen<focus.max
  if CDsON() and S.DeathChakram:IsCastable() and (CheckFocusCap(S.DeathChakram:ExecuteTime())) then
    if Cast(S.DeathChakram, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "death_chakram apst 2"; end
  end
  -- serpent_sting,target_if=min:remains,if=!dot.serpent_sting.ticking&target.time_to_die>7
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingAPST) then return "serpent_sting apst 4"; end
  end
  if CDsON() then
    -- flayed_shot
    if S.FlayedShot:IsCastable() then
      if Cast(S.FlayedShot, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "flayed_shot apst 6"; end
    end
    -- resonating_arrow
    if S.ResonatingArrow:IsCastable() then
      if Cast(S.ResonatingArrow, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "resonating_arrow apst 8"; end
    end
    -- wild_spirits
    if S.WildSpirits:IsCastable() then
      if Cast(S.WildSpirits, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "wild_spirits apst 10"; end
    end
    -- coordinated_assault
    if S.CoordinatedAssault:IsCastable() then
      if Cast(S.CoordinatedAssault, Settings.Survival.GCDasOffGCD.CoordinatedAssault) then return "coordinated_assault apst 12"; end
    end
  end
  -- kill_shot,if=target.health.pct<=20
  if S.KillShot:IsReady() and Target:HealthPercentage() <= 20 then
    if Cast(S.KillShot, nil, nil, not Target:IsInRange(40)) then return "kill_shot apst 14"; end
  end
  -- flanking_strike,if=focus+cast_regen<focus.max
  if S.FlankingStrike:IsCastable() and (CheckFocusCap(S.FlankingStrike:ExecuteTime())) then
    if Cast(S.FlankingStrike, nil, nil, not Target:IsInRange(15)) then return "flanking_strike apst 16"; end
  end
  -- a_murder_of_crows
  if S.AMurderofCrows:IsCastable() then
    if Cast(S.AMurderofCrows, Settings.Survival.GCDasOffGCD.AMurderofCrows, nil, not Target:IsInRange(40)) then return "a_murder_of_crows apst 18"; end
  end
  -- wildfire_bomb,if=full_recharge_time<gcd|focus+cast_regen<focus.max&(next_wi_bomb.volatile&dot.serpent_sting.ticking&dot.serpent_sting.refreshable|next_wi_bomb.pheromone&!buff.mongoose_fury.up&focus+cast_regen<focus.max-action.kill_command.cast_regen*3)|time_to_die<10
  if S.PheromoneBomb:IsReady() and (S.WildfireBomb:FullRechargeTime() < Player:GCD() or CheckFocusCap(S.WildfireBomb:ExecuteTime()) and Player:BuffDown(S.MongooseFuryBuff) and Player:Focus() + Player:FocusCastRegen(S.WildfireBomb:ExecuteTime()) < Player:FocusMax() - Player:FocusCastRegen(S.KillCommand:ExecuteTime()) * 3 or Target:TimeToDie() < 10) then
    if Cast(S.PheromoneBomb, nil, nil, not Target:IsInRange(40)) then return "pheromone_bomb apst 20"; end
  end
  if S.VolatileBomb:IsReady() and (S.WildfireBomb:FullRechargeTime() < Player:GCD() or CheckFocusCap(S.WildfireBomb:ExecuteTime()) and Target:DebuffUp(S.SerpentStingDebuff) and Target:DebuffRefreshable(S.SerpentStingDebuff) or Target:TimeToDie() < 10) then
    if Cast(S.VolatileBomb, nil, nil, not Target:IsSpellInRange(S.VolatileBomb)) then return "volatile_bomb apst 22"; end
  end
  -- carve,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped
  if S.Carve:IsReady() and (EnemyCount8y > 1 and not RylakstalkersConfoundingEquipped) then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve apst 24"; end
  end
  -- butchery,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped&cooldown.wildfire_bomb.full_recharge_time>spell_targets&(charges_fractional>2.5|dot.shrapnel_bomb.ticking)
  if S.Butchery:IsReady() and (EnemyCount8y > 1 and not RylakstalkersConfoundingEquipped and S.WildfireBomb:FullRechargeTime() > EnemyCount8y and (S.Butchery:ChargesFractional() > 2.5 or Target:DebuffUp(S.ShrapnelBombDebuff))) then
    if Cast(S.Butchery, nil, nil, not Target:IsInRange(8)) then return "butchery apst 26"; end
  end
  -- steel_trap,if=focus+cast_regen<focus.max
  if S.SteelTrap:IsCastable() and (CheckFocusCap(S.SteelTrap:ExecuteTime())) then
    if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap apst 28"; end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.mongoose_fury.up&buff.mongoose_fury.remains<focus%(action.mongoose_bite.cost-cast_regen)*gcd&!buff.wild_spirits.remains|buff.mongoose_fury.remains&next_wi_bomb.pheromone
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfMongooseBiteAPST) then return "mongoose_bite apst 30"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=full_recharge_time<gcd&focus+cast_regen<focus.max
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateKillCommandCycleCondition1) then return "kill_command apst 32"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.tip_of_the_spear.stack=3|dot.shrapnel_bomb.ticking
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfRaptorStrikeAPST) then return "raptor_strike apst 34"; end
  end
  -- mongoose_bite,if=dot.shrapnel_bomb.ticking
  if S.MongooseBite:IsReady() and (Target:DebuffUp(S.ShrapnelBombDebuff)) then
    if Cast(S.MongooseBite, nil, nil, not Target:IsInRange(40)) then return "mongoose_bite apst 36"; end
  end
  -- serpent_sting,target_if=min:remains,if=refreshable&target.time_to_die>7
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingAPST2) then return "serpent_sting apst 38"; end
  end
  -- wildfire_bomb,if=next_wi_bomb.shrapnel&focus>action.mongoose_bite.cost*2&dot.serpent_sting.remains>5*gcd
  if S.ShrapnelBomb:IsCastable() and (Player:Focus() > S.MongooseBite:Cost() * 2 and Target:DebuffRemains(S.SerpentStingDebuff) > 5 * Player:GCD()) then
    if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb apst 40"; end
  end
  -- chakrams
  if S.Chakrams:IsReady() then
    if Cast(S.Chakrams, nil, nil, not Target:IsInRange(40)) then return "chakrams apst 42"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateTargetIfKillCommandAPST) then return "kill_command apst 44"; end
  end
  -- wildfire_bomb,if=runeforge.rylakstalkers_confounding_strikes.equipped
  if RylakstalkersConfoundingEquipped then
    if S.ShrapnelBomb:IsCastable() then
      if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb apst 46"; end
    end
    if S.PheromoneBomb:IsCastable() then
      if Cast(S.PheromoneBomb, nil, nil, not Target:IsInRange(40)) then return "pheromone_bomb apst 48"; end
    end
    if S.VolatileBomb:IsCastable() then
      if Cast(S.VolatileBomb, nil, nil, not Target:IsInRange(40)) then return "volatile_bomb apst 50"; end
    end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max-15|dot.shrapnel_bomb.ticking|buff.wild_spirits.remains
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfMongooseBiteAPST2) then return "mongoose_bite apst 52"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "raptor_strike apst 54"; end
  end
  -- wildfire_bomb,if=next_wi_bomb.volatile&dot.serpent_sting.ticking|next_wi_bomb.pheromone|next_wi_bomb.shrapnel&focus>50
  if S.VolatileBomb:IsCastable() and (Target:DebuffUp(S.SerpentStingDebuff)) then
    if Cast(S.VolatileBomb, nil, nil, not Target:IsInRange(40)) then return "volatile_bomb apst 56"; end
  end
  if S.PheromoneBomb:IsCastable() then
    if Cast(S.PheromoneBomb, nil, nil, not Target:IsInRange(40)) then return "pheromone_bomb apst 58"; end
  end
  if S.ShrapnelBomb:IsCastable() and (Player:Focus() > 50) then
    if Cast(S.ShrapnelBomb, nil, nil, not Target:IsInRange(40)) then return "shrapnel_bomb apst 60"; end
  end
end

local function BOP()
  -- serpent_sting,target_if=min:remains,if=buff.vipers_venom.remains&(buff.vipers_venom.remains<gcd|refreshable)
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingBOP) then return "serpent_sting bop 2"; end
  end
  -- kill_shot
  if S.KillShot:IsReady() then
    if Cast(S.KillShot, nil, nil, not Target:IsInRange(40)) then return "kill_shot bop 4"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&buff.nesingwarys_trapping_apparatus.up
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateTargetIfKillCommandBOP) then return "kill_command bop 6"; end
  end
  -- wildfire_bomb,if=focus+cast_regen<focus.max&!ticking&full_recharge_time<gcd
  if S.WildfireBomb:IsCastable() and (CheckFocusCap(S.WildfireBomb:ExecuteTime()) and Target:DebuffDown(S.WildfireBombDebuff) and S.WildfireBomb:FullRechargeTime() < Player:GCD()) then
    if Cast(S.WildfireBomb, nil, nil, not Target:IsInRange(40)) then return "wildfire_bomb bop 8"; end
  end
  -- flanking_strike,if=focus+cast_regen<focus.max
  if S.FlankingStrike:IsCastable() and (CheckFocusCap(S.FlankingStrike:ExecuteTime())) then
    if Cast(S.FlankingStrike, nil, nil, not Target:IsInRange(15)) then return "flanking_strike bop 10"; end
  end
  -- flayed_shot
  if CDsON() and S.FlayedShot:IsCastable() then
    if Cast(S.FlayedShot, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "flayed_shot bop 12"; end
  end
  -- call_action_list,name=nta,if=runeforge.nessingwarys_trapping_apparatus.equipped&focus<action.mongoose_bite.cost 
  if (NessingwarysTrappingEquipped and Player:Focus() < S.MongooseBite:Cost()) then
    local ShouldReturn = nta(); if ShouldReturn then return ShouldReturn; end
  end
  -- death_chakram,if=focus+cast_regen<focus.max
  if CDsON() and S.DeathChakram:IsCastable() and (CheckFocusCap(S.DeathChakram:ExecuteTime())) then
    if Cast(S.DeathChakram, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "death_chakram bop 14"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.coordinated_assault.up&buff.coordinated_assault.remains<1.5*gcd
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfRaptorStrikeBOP) then return "raptor_strike bop 16"; end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.coordinated_assault.up&buff.coordinated_assault.remains<1.5*gcd
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks, EvaluateTargetIfRaptorStrikeBOP) then return "mongoose_bite bop 18"; end
  end
  -- a_murder_of_crows
  if S.AMurderofCrows:IsReady() then
    if Cast(S.AMurderofCrows, Settings.Commons.GCDasOffGCD.AMurderofCrows, nil, not Target:IsInRange(40)) then return "a_murder_of_crows bop 20"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.tip_of_the_spear.stack=3
  if S.RaptorStrike:IsReady() and (Player:BuffStack(S.TipoftheSpearBuff) == 3) then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "raptor_strike bop 22"; end
  end
  -- wildfire_bomb,if=focus+cast_regen<focus.max&!ticking&(full_recharge_time<gcd|!dot.wildfire_bomb.ticking&buff.mongoose_fury.remains>full_recharge_time-1*gcd|!dot.wildfire_bomb.ticking&!buff.mongoose_fury.remains)|time_to_die<18&!dot.wildfire_bomb.ticking
  if S.WildfireBomb:IsCastable() and (CheckFocusCap(S.WildfireBomb:ExecuteTime()) and Target:DebuffDown(S.WildfireBombDebuff) and (S.WildfireBomb:FullRechargeTime() < Player:GCD() or Target:DebuffDown(S.WildfireBombDebuff) and Player:BuffRemains(S.MongooseFuryBuff) > S.WildfireBomb:FullRechargeTime() - Player:GCD() or Target:DebuffDown(S.WildfireBombDebuff) and Player:BuffDown(S.MongooseFuryBuff)) or Target:TimeToDie() < 18 and Target:DebuffDown(S.WildfireBombDebuff)) then
    if Cast(S.WildfireBomb, nil, nil, not Target:IsInRange(40)) then return "wildfire_bomb bop 24"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&!runeforge.nessingwarys_trapping_apparatus.equipped|focus+cast_regen<focus.max&((runeforge.nessingwarys_trapping_apparatus.equipped&!talent.steel_trap.enabled&cooldown.freezing_trap.remains&cooldown.tar_trap.remains)|(runeforge.nessingwarys_trapping_apparatus.equipped&talent.steel_trap.enabled&cooldown.freezing_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd&cooldown.tar_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd&cooldown.steel_trap.remains>focus%(action.mongoose_bite.cost-cast_regen)*gcd))|focus<action.mongoose_bite.cost
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateTargetIfKillCommandBOP2) then return "kill_command bop 26"; end
  end
  -- steel_trap,if=focus+cast_regen<focus.max
  if S.SteelTrap:IsCastable() and (CheckFocusCap(S.SteelTrap:ExecuteTime())) then
    if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap bop 28"; end
  end
  -- serpent_sting,target_if=min:remains,if=dot.serpent_sting.refreshable&!buff.coordinated_assault.up
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingBOP2) then return "serpent_sting bop 30"; end
  end
  if CDsON() then
    -- resonating_arrow
    if S.ResonatingArrow:IsCastable() then
      if Cast(S.ResonatingArrow, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "resonating_arrow bop 32"; end
    end
    -- wild_spirits
    if S.WildSpirits:IsCastable() then
      if Cast(S.WildSpirits, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "wild_spirits bop 34"; end
    end
    -- coordinated_assault,if=!buff.coordinated_assault.up
    if S.CoordinatedAssault:IsCastable() then
      if Cast(S.CoordinatedAssault, Settings.Survival.GCDasOffGCD.CoordinatedAssault) then return "coordinated_assault bop 36"; end
    end
  end
  -- mongoose_bite,if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max|buff.coordinated_assault.up
  if S.MongooseBite:IsReady() and (Player:BuffUp(S.MongooseFuryBuff) or Player:Focus() + Player:FocusCastRegen(S.KillCommand:ExecuteTime()) > Player:FocusMax() or Player:BuffUp(S.CoordinatedAssault)) then
    if Cast(S.MongooseBite, nil, nil, not Target:IsInMeleeRange(5)) then return "mongoose_bite bop 38"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "raptor_strike bop 40"; end
  end
  -- wildfire_bomb,if=dot.wildfire_bomb.refreshable
  if S.WildfireBomb:IsCastable() and (Target:DebuffRefreshable(S.WildfireBombDebuff)) then
    if Cast(S.WildfireBomb, nil, nil, not Target:IsInRange(40)) then return "wildfire_bomb bop 42"; end
  end
  -- serpent_sting,target_if=min:remains,if=buff.vipers_venom.up
  if S.SerpentSting:IsReady() and (Player:BuffUp(S.VipersVenomBuff)) then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains) then return "serpent_sting bop 44"; end
  end
end

local function Cleave()
  -- serpent_sting,target_if=min:remains,if=talent.hydras_bite.enabled&buff.vipers_venom.remains&buff.vipers_venom.remains<gcd
  if S.SerpentSting:IsReady() and (S.HydrasBite:IsAvailable() and Player:BuffUp(S.VipersVenomBuff) and Player:BuffRemains(S.VipersVenomBuff) < Player:GCD()) then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains) then return "serpent_sting cleave 2"; end
  end
  if CDsON() then
    -- wild_spirits
    if S.WildSpirits:IsCastable() then
      if Cast(S.WildSpirits, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "wild_spirits cleave 4"; end
    end
    -- resonating_arrow
    if S.ResonatingArrow:IsCastable() then
      if Cast(S.ResonatingArrow, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "resonating_arrow cleave 6"; end
    end
  end
  -- wildfire_bomb,if=full_recharge_time<gcd
  if S.WildfireBomb:IsReady() and not S.WildfireInfusion:IsAvailable() and (S.WildfireBomb:FullRechargeTime() < Player:GCD()) then
    if Cast(S.WildfireBomb, nil, nil, not Target:IsInRange(40)) then return "wildfire_bomb cleave 8"; end
  end
  -- chakrams
  if S.Chakrams:IsReady() then
    if Cast(S.Chakrams, nil, nil, not Target:IsInRange(15)) then return "chakrams cleave 10"; end
  end
  -- butchery,if=dot.shrapnel_bomb.ticking&(dot.internal_bleeding.stack<2|dot.shrapnel_bomb.remains<gcd)
  if S.Butchery:IsReady() and (Target:DebuffUp(S.ShrapnelBombDebuff) and (Target:DebuffStack(S.InternalBleedingDebuff) < 2 or Target:DebuffRemains(S.ShrapnelBombDebuff) < Player:GCD())) then
    if Cast(S.Butchery, nil, nil, not Target:IsInRange(8)) then return "butchery cleave 12"; end
  end
  -- carve,if=dot.shrapnel_bomb.ticking
  if S.Carve:IsReady() and (Target:DebuffUp(S.ShrapnelBombDebuff)) then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve cleave 14"; end
  end
  if CDsON() then
    -- death_chakram,if=focus+cast_regen<focus.max
    if S.DeathChakram:IsCastable() and (CheckFocusCap(S.DeathChakram:ExecuteTime())) then
      if Cast(S.DeathChakram, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "death_chakram cleave 16"; end
    end
    -- coordinated_assault
    if S.CoordinatedAssault:IsReady() then
      if Cast(S.CoordinatedAssault, Settings.Survival.GCDasOffGCD.CoordinatedAssault) then return "coordinated_assault cleave 18"; end
    end
  end
  -- butchery,if=charges_fractional>2.5&cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
  if S.Butchery:IsReady() and (S.Butchery:ChargesFractional() > 2.5 and S.WildfireBomb:FullRechargeTime() > EnemyCount8y / 2) then
    if Cast(S.Butchery, nil, nil, not Target:IsInRange(8)) then return "butchery cleave 20"; end
  end
  -- flanking_strike,if=focus+cast_regen<focus.max
  if S.FlankingStrike:IsCastable() and (CheckFocusCap(S.FlankingStrike:ExecuteTime())) then
    if Cast(S.FlankingStrike, nil, nil, not Target:IsInRange(15)) then return "flanking_strike cleave 22"; end
  end
  -- carve,if=cooldown.wildfire_bomb.full_recharge_time>spell_targets%2&talent.alpha_predator.enabled
  if S.Carve:IsReady() and (S.WildfireBomb:FullRechargeTime() > EnemyCount8y / 2 and S.AlphaPredator:IsAvailable()) then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve cleave 24"; end
  end
  -- kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&full_recharge_time<gcd&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
  if S.KillCommand:IsCastable() then
    if Everyone.CastTargetIf(S.KillCommand, Enemy8y, "min", EvaluateTargetIfFilterKillCommandRemains, EvaluateTargetIfKillCommandCleave) then return "kill_command cleave 26"; end
  end
  -- wildfire_bomb,if=!dot.wildfire_bomb.ticking
  if S.WildfireBomb:IsCastable() and (Target:DebuffDown(S.WildfireBombDebuff)) then
    if Cast(S.WildfireBomb, nil, nil, not Target:IsInRange(40)) then return "wildfire_bomb cleave 28"; end
  end
  -- butchery,if=(!next_wi_bomb.shrapnel|!talent.wildfire_infusion.enabled)&cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
  if S.Butchery:IsReady() and ((not S.ShrapnelBomb:IsCastable() or not S.WildfireInfusion:IsAvailable()) and S.WildfireBomb:FullRechargeTime() > EnemyCount8y / 2) then
    if Cast(S.Butchery, nil, nil, not Target:IsInRange(8)) then return "butchery cleave 30"; end
  end
  -- carve,if=cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
  if S.Carve:IsReady() and (S.WildfireBomb:FullRechargeTime() > EnemyCount8y / 2) then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve cleave 32"; end
  end
  -- kill_shot
  if S.KillShot:IsReady() then
    if Cast(S.KillShot, nil, nil, not Target:IsInRange(40)) then return "kill_shot cleave 34"; end
  end
  -- flayed_shot
  if CDsON() and S.FlayedShot:IsCastable() then
    if Cast(S.FlayedShot, nil, Settings.Commons.DisplayStyle.Covenant, not Target:IsInRange(40)) then return "flayed_shot cleave 36"; end
  end
  -- a_murder_of_crows
  if S.AMurderofCrows:IsReady() then
    if Cast(S.AMurderofCrows, Settings.Commons.GCDasOffGCD.AMurderofCrows, nil, not Target:IsInRange(40)) then return "a_murder_of_crows cleave 38"; end
  end
  -- steel_trap
  if S.SteelTrap:IsCastable() then
    if Cast(S.SteelTrap, nil, nil, not Target:IsInRange(40)) then return "steel_trap cleave 40"; end
  end
  -- serpent_sting,target_if=min:remains,if=refreshable&talent.hydras_bite.enabled&target.time_to_die>8
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingCleave) then return "serpent_sting cleave 42"; end
  end
  -- carve
  if S.Carve:IsReady() then
    if Cast(S.Carve, nil, nil, not Target:IsInRange(8)) then return "carve cleave 44"; end
  end
  -- kill_command,target_if=focus+cast_regen<focus.max&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
  if S.KillCommand:IsCastable() then
    if Everyone.CastCycle(S.KillCommand, Enemy8y, EvaluateCycleKillCommandCleave, not Target:IsInRange(50)) then return "kill_command cleave 46"; end
  end
  -- serpent_sting,target_if=min:remains,if=refreshable
  if S.SerpentSting:IsReady() then
    if Everyone.CastTargetIf(S.SerpentSting, Enemy8y, "min", EvaluateTargetIfFilterSerpentStingRemains, EvaluateTargetIfSerpentStingCleave2) then return "serpent_sting cleave 48"; end
  end
  -- mongoose_bite,target_if=max:debuff.latent_poison_injection.stack
  if S.MongooseBite:IsReady() then
    if Everyone.CastTargetIf(S.MongooseBite, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "mongoose_bite cleave 50"; end
  end
  -- raptor_strike,target_if=max:debuff.latent_poison_injection.stack
  if S.RaptorStrike:IsReady() then
    if Everyone.CastTargetIf(S.RaptorStrike, Enemy8y, "max", EvaluateTargetIfFilterRaptorStrikeLatentStacks) then return "raptor_strike cleave 52"; end
  end
end

local function APL()
  -- Target Count Checking
  Enemy8y = Player:GetEnemiesInRange(8)
  if AoEON() then
    EnemyCount8y = #Enemy8y
  else
    EnemyCount8y = 1
  end

  -- call precombat
  if not Player:AffectingCombat() then
    local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
  end

  -- Exhilaration
  if S.Exhilaration:IsCastable() and Player:HealthPercentage() <= Settings.Commons2.ExhilarationHP then
    if Cast(S.Exhilaration, Settings.Commons2.GCDasOffGCD.Exhilaration) then return "Exhilaration"; end
  end
  if Everyone.TargetIsValid() then
    -- muzzle
    local ShouldReturn = Everyone.Interrupt(5, S.Muzzle, Settings.Survival.OffGCDasOffGCD.Muzzle, StunInterrupts); if ShouldReturn then return ShouldReturn; end
    -- auto_attack
    -- use_items
    if CDsON() and Settings.Commons.Enabled.Trinkets then
      local TrinketToUse = Player:GetUseableTrinkets(TrinketsOnUseExcludes)
      if TrinketToUse then
        if Cast(TrinketToUse, nil, Settings.Commons.DisplayStyle.Trinkets) then return "Generic use_items for " .. TrinketToUse:Name(); end
      end
    end
    -- call_action_list,name=cds
    if (CDsON()) then
      local ShouldReturn = CDs(); if ShouldReturn then return ShouldReturn; end
    end
    -- call_action_list,name=bop,if=active_enemies<3&talent.birds_of_prey.enabled
    if (EnemyCount8y < 3 and S.BirdsofPrey:IsAvailable()) then
      local ShouldReturn = BOP(); if ShouldReturn then return ShouldReturn; end
    end
    -- call_action_list,name=apst,if=active_enemies<3&talent.alpha_predator.enabled&!talent.birds_of_prey.enabled
    if (EnemyCount8y < 3 and S.AlphaPredator:IsAvailable() and not S.BirdsofPrey:IsAvailable()) then
      local ShouldReturn = APST(); if ShouldReturn then return ShouldReturn; end
    end
    -- call_action_list,name=st,if=active_enemies<3&!talent.birds_of_prey.enabled
    if (EnemyCount8y < 3 and not S.AlphaPredator:IsAvailable() and not S.BirdsofPrey:IsAvailable()) then
      local ShouldReturn = ST(); if ShouldReturn then return ShouldReturn; end
    end
    -- call_action_list,name=cleave,if=active_enemies>2
    if (EnemyCount8y > 2) then
      local ShouldReturn = Cleave(); if ShouldReturn then return ShouldReturn; end
    end
    -- arcane_torrent
    if S.ArcaneTorrent:IsCastable() and CDsON() then
      if Cast(S.ArcaneTorrent, Settings.Commons.OffGCDasOffGCD.Racials, nil, not Target:IsInRange(8)) then return "arcane_torrent 888"; end
    end
    if Cast(S.PoolFocus) then return "Pooling Focus"; end
  end
end

local function OnInit ()
  HL.Print("Survival APL is WIP.")
end

HR.SetAPL(255, APL, OnInit)
