-- Ess/08_ecs.lua -- Ess.Ecs: the engine's ECS component-class registry as a typed vocabulary.
--
-- An entity is ASSEMBLED from reflection component classes -- RuntimeHealth, StateMachine, Explosive,
-- AiPatrol, ... -- ~232 of them, grouped into 9 families. This is that catalogue: each class with its
-- family and its component HASH (`pandemic_hash_m2(name)`, the value the engine's component resolver keys
-- on -- verified against the RE: Health=0x06BE1ABF, RuntimeHealth=0xF9B9B2A5, RuntimeNodeHealth=0x76927BF5).
-- It is the "what is a live entity MADE OF" vocabulary -- the typed half of the remote inspector.
--
-- ⚠ SCOPE -- this is the NAMING half. A generic RAW per-entity component READ (dump an arbitrary component's
-- fields off an arbitrary entity) needs a native memory-read verb the bridge does not yet expose. The path
-- IS reversed -- an object->component resolver and the entity's 256-slot component table -- and these hashes
-- are the keys it takes; until such a native lands, `Ess.Inspect` reads the components the engine already
-- exposes through getters. Ess.Ecs ships the vocabulary those tools name things with.
--
-- API:
--   Ess.Ecs.classes()      -> the full { {n=,f=,h=}, ... } list (name, family, hash)
--   Ess.Ecs.get(name)      -> {n,f,h} | nil        one class, exact, case-insensitive
--   Ess.Ecs.hash(name)     -> "0xHASH" | nil        the component's m2 hash (what the resolver keys on)
--   Ess.Ecs.family(name)   -> sFamily | nil         which of the 9 families a class is in
--   Ess.Ecs.find(query)    -> { class, ... }         classes whose name OR family contains query (ci)
--   Ess.Ecs.families()     -> { sFamily, ... }       the 9 family names, sorted
--
-- The CLASSES table below is GENERATED from data/ecs_registry.tsv (the Mercs2 reflection RE, docs/mercs2-ecs)
-- by build/ecs.py -- rerun it and paste over the block when the registry changes; do not hand-edit the rows.

local Ess = _G.Ess

Ess.Ecs = Ess.Ecs or {}

local CLASSES = {
  { n = "AiBehavior", f = "ai_perception_population", h = "0xDECD8889" },
  { n = "AiDriving", f = "ai_perception_population", h = "0x67AB955C" },
  { n = "AiHelicopter", f = "ai_perception_population", h = "0x78EB1ADC" },
  { n = "AiPatrol", f = "ai_perception_population", h = "0xB0CA290D" },
  { n = "AiSkill", f = "ai_perception_population", h = "0xEBA09B1A" },
  { n = "AiUnUsable", f = "ai_perception_population", h = "0x4A548962" },
  { n = "AiWaterZone", f = "ai_perception_population", h = "0xDF6533DE" },
  { n = "ChatterSet", f = "ai_perception_population", h = "0x949A1E44" },
  { n = "MeleeCombatant", f = "ai_perception_population", h = "0xBF438E92" },
  { n = "Perception", f = "ai_perception_population", h = "0x3F6AB8F0" },
  { n = "PopulationDensity", f = "ai_perception_population", h = "0x6FA2F9D4" },
  { n = "PopulationDynamicRoad", f = "ai_perception_population", h = "0xFFC5BAA5" },
  { n = "PopulationFlow", f = "ai_perception_population", h = "0x322750EC" },
  { n = "RtLivingWorld", f = "ai_perception_population", h = "0x115B2B5C" },
  { n = "RtPopHint", f = "ai_perception_population", h = "0x036DC9CB" },
  { n = "RtPopMembership", f = "ai_perception_population", h = "0x8C8E5490" },
  { n = "RuntimeTravelGroup", f = "ai_perception_population", h = "0x5F187FA4" },
  { n = "SkirmishSpawnList", f = "ai_perception_population", h = "0xAFBA5846" },
  { n = "SkirmishZone", f = "ai_perception_population", h = "0xFC5923AF" },
  { n = "SocialUse", f = "ai_perception_population", h = "0x7E6BF93D" },
  { n = "Squad", f = "ai_perception_population", h = "0x9788C501" },
  { n = "Stimulus", f = "ai_perception_population", h = "0x06408D71" },
  { n = "StimulusModifier", f = "ai_perception_population", h = "0xB9388F0A" },
  { n = "Suspect", f = "ai_perception_population", h = "0x1AFC276C" },
  { n = "Target", f = "ai_perception_population", h = "0xAFF6B246" },
  { n = "ExplosionFudge", f = "combat_weapons_projectiles", h = "0x5AEABC23" },
  { n = "Explosive", f = "combat_weapons_projectiles", h = "0xF74044BA" },
  { n = "FlareObject", f = "combat_weapons_projectiles", h = "0x9F3EBFBA" },
  { n = "HomingProjectile", f = "combat_weapons_projectiles", h = "0xE81B2874" },
  { n = "HomingTarget", f = "combat_weapons_projectiles", h = "0xB9EA3B32" },
  { n = "HomingWeapon", f = "combat_weapons_projectiles", h = "0x1A4DB6ED" },
  { n = "Ignitor", f = "combat_weapons_projectiles", h = "0x37C12455" },
  { n = "InitialVelocity", f = "combat_weapons_projectiles", h = "0x6537A65A" },
  { n = "ProjectilePhysics", f = "combat_weapons_projectiles", h = "0x11E6C283" },
  { n = "RuntimeAirstrikeAirplane", f = "combat_weapons_projectiles", h = "0x23D5DE91" },
  { n = "RuntimeAirstrikeProjectile", f = "combat_weapons_projectiles", h = "0xF67A894A" },
  { n = "RuntimeAlternatingFire", f = "combat_weapons_projectiles", h = "0x9BB55CF2" },
  { n = "RuntimeExplosion", f = "combat_weapons_projectiles", h = "0x5529DD38" },
  { n = "RuntimeFakeProjectile", f = "combat_weapons_projectiles", h = "0x750BC641" },
  { n = "RuntimeHomingProjectile", f = "combat_weapons_projectiles", h = "0xC45D369E" },
  { n = "RuntimeHomingTarget", f = "combat_weapons_projectiles", h = "0x14F6DE44" },
  { n = "RuntimeHomingWeapon", f = "combat_weapons_projectiles", h = "0xC09ADB1B" },
  { n = "RuntimeIgnitor", f = "combat_weapons_projectiles", h = "0x1CA3ABD7" },
  { n = "RuntimeLaserDesignator", f = "combat_weapons_projectiles", h = "0x735B0EAA" },
  { n = "RuntimeProjectile", f = "combat_weapons_projectiles", h = "0x9D2AB1A6" },
  { n = "RuntimeProjectileThrown", f = "combat_weapons_projectiles", h = "0xF394DE30" },
  { n = "RuntimeVelocity", f = "combat_weapons_projectiles", h = "0xE493BF82" },
  { n = "RuntimeWeapon", f = "combat_weapons_projectiles", h = "0xEC62E3A3" },
  { n = "RuntimeWeaponProjectile", f = "combat_weapons_projectiles", h = "0x7A303AD6" },
  { n = "WeaponBarrel", f = "combat_weapons_projectiles", h = "0x180E2B95" },
  { n = "WeaponEffects", f = "combat_weapons_projectiles", h = "0xF24D2021" },
  { n = "WeaponHint", f = "combat_weapons_projectiles", h = "0xD390834A" },
  { n = "WeaponProjectileBase", f = "combat_weapons_projectiles", h = "0xEB505C8B" },
  { n = "WeaponRecoilVehicle", f = "combat_weapons_projectiles", h = "0x557E4B99" },
  { n = "WeaponScatter", f = "combat_weapons_projectiles", h = "0xE7234615" },
  { n = "WeaponScope", f = "combat_weapons_projectiles", h = "0x27CA777F" },
  { n = "WeaponThrown", f = "combat_weapons_projectiles", h = "0x24870CFF" },
  { n = "WeaponTrigger", f = "combat_weapons_projectiles", h = "0xC526A637" },
  { n = "WeaponUI", f = "combat_weapons_projectiles", h = "0xE5D5E31F" },
  { n = "Anchor", f = "controllers_physics", h = "0xFA55F6BA" },
  { n = "BoneControllerRuntime", f = "controllers_physics", h = "0x09A0962D" },
  { n = "BoneCtrlPhysicsActor", f = "controllers_physics", h = "0x1AFAED2A" },
  { n = "Buoyancy", f = "controllers_physics", h = "0xB9659F7B" },
  { n = "CenterOfMassInWorld", f = "controllers_physics", h = "0xE5276B5C" },
  { n = "ControllerBoat", f = "controllers_physics", h = "0x4F89A7C7" },
  { n = "ControllerCar", f = "controllers_physics", h = "0xEEEA744D" },
  { n = "ControllerHelicopter", f = "controllers_physics", h = "0x495A0CEA" },
  { n = "ControllerLW", f = "controllers_physics", h = "0x1BB0A5BE" },
  { n = "ControllerLadder", f = "controllers_physics", h = "0x964E010D" },
  { n = "ControllerPlayer", f = "controllers_physics", h = "0x6CA511B2" },
  { n = "ControllerTank", f = "controllers_physics", h = "0x55BC62BD" },
  { n = "ControllerVehicle", f = "controllers_physics", h = "0xBFB1AECB" },
  { n = "ControllerVelocity", f = "controllers_physics", h = "0xD61C71B4" },
  { n = "Crusher", f = "controllers_physics", h = "0x24463D8B" },
  { n = "MassiveComponent", f = "controllers_physics", h = "0xF482C286" },
  { n = "PhysicsActor", f = "controllers_physics", h = "0xFE9497DB" },
  { n = "PhysicsActorRagdoll", f = "controllers_physics", h = "0xF365E0EC" },
  { n = "PhysicsActorWinch", f = "controllers_physics", h = "0x025B7AB6" },
  { n = "PhysicsDefaultActivator", f = "controllers_physics", h = "0x2E2659F0" },
  { n = "PhysicsPropertyFakeContinuous", f = "controllers_physics", h = "0x639F9491" },
  { n = "PhysicsPropertyGravityScaler", f = "controllers_physics", h = "0x841BA027" },
  { n = "PhysicsPropertyUncrushable", f = "controllers_physics", h = "0xA61BD97B" },
  { n = "RTHuman", f = "controllers_physics", h = "0x2C6E46B6" },
  { n = "RagdollController", f = "controllers_physics", h = "0x34EA185E" },
  { n = "RtDebris", f = "controllers_physics", h = "0x964BEBAA" },
  { n = "RtDriverData", f = "controllers_physics", h = "0xE2636501" },
  { n = "RtJunction", f = "controllers_physics", h = "0x643B62AF" },
  { n = "RuntimeMassiveSubscriber", f = "controllers_physics", h = "0x4172E975" },
  { n = "Sticky", f = "controllers_physics", h = "0x97870D10" },
  { n = "Winch", f = "controllers_physics", h = "0x9C6B3368" },
  { n = "Alarm", f = "gameplay_state_health_mission", h = "0xBE65FDD0" },
  { n = "BuildingDestruction", f = "gameplay_state_health_mission", h = "0x17A5555B" },
  { n = "CashValue", f = "gameplay_state_health_mission", h = "0x564990C3" },
  { n = "ContextAction", f = "gameplay_state_health_mission", h = "0xF957A94C" },
  { n = "ControlBinding", f = "gameplay_state_health_mission", h = "0x3486768B" },
  { n = "DamageKey", f = "gameplay_state_health_mission", h = "0xEF41976F" },
  { n = "DangerousBuilding", f = "gameplay_state_health_mission", h = "0x543977F7" },
  { n = "FactionMarker", f = "gameplay_state_health_mission", h = "0x9B98CB09" },
  { n = "FactionValue", f = "gameplay_state_health_mission", h = "0x8BFC69D6" },
  { n = "FactionZone", f = "gameplay_state_health_mission", h = "0x67267CC1" },
  { n = "FlightNoise", f = "gameplay_state_health_mission", h = "0x10ED85AF" },
  { n = "Health", f = "gameplay_state_health_mission", h = "0x06BE1ABF" },
  { n = "HibernationControl", f = "gameplay_state_health_mission", h = "0xE18AFD65" },
  { n = "LandingZone", f = "gameplay_state_health_mission", h = "0x2A20B640" },
  { n = "NetCategoryInfo", f = "gameplay_state_health_mission", h = "0x99CDCA52" },
  { n = "ObjectScript", f = "gameplay_state_health_mission", h = "0xD81512A1" },
  { n = "RtAlarm", f = "gameplay_state_health_mission", h = "0x7A3425CE" },
  { n = "RtDamageFlags", f = "gameplay_state_health_mission", h = "0x93621235" },
  { n = "RtFactionZone", f = "gameplay_state_health_mission", h = "0xA67114C7" },
  { n = "RuntimeAssetRef", f = "gameplay_state_health_mission", h = "0xD2435030" },
  { n = "RuntimeClaim", f = "gameplay_state_health_mission", h = "0x5D5CB7BD" },
  { n = "RuntimeFlightNoise", f = "gameplay_state_health_mission", h = "0xEBF6D595" },
  { n = "RuntimeHealth", f = "gameplay_state_health_mission", h = "0xF9B9B2A5" },
  { n = "RuntimeHijackState", f = "gameplay_state_health_mission", h = "0xD5F2B17A" },
  { n = "RuntimeLastDamageApplied", f = "gameplay_state_health_mission", h = "0x9CBD437B" },
  { n = "RuntimeNodeHealth", f = "gameplay_state_health_mission", h = "0x76927BF5" },
  { n = "RuntimeObjectiveMarker", f = "gameplay_state_health_mission", h = "0x2A77B292" },
  { n = "RuntimeOwnerGuid", f = "gameplay_state_health_mission", h = "0xAFF006A7" },
  { n = "RuntimeRope", f = "gameplay_state_health_mission", h = "0xA9C2A15B" },
  { n = "RuntimeScriptCallback", f = "gameplay_state_health_mission", h = "0x3B105827" },
  { n = "RuntimeScrub", f = "gameplay_state_health_mission", h = "0x7DA4BD48" },
  { n = "RuntimeTerrainBound", f = "gameplay_state_health_mission", h = "0x745C6D6A" },
  { n = "RuntimeTimer", f = "gameplay_state_health_mission", h = "0x38437A4E" },
  { n = "ScrubObject", f = "gameplay_state_health_mission", h = "0xAB92C697" },
  { n = "StateMachine", f = "gameplay_state_health_mission", h = "0x98A3661F" },
  { n = "Disable3DDecals", f = "misc_uncategorized", h = "0x69A0E0E4" },
  { n = "DisableDecals", f = "misc_uncategorized", h = "0xFF4533E5" },
  { n = "RuntimeAnimationParams", f = "misc_uncategorized", h = "0x9606E589" },
  { n = "TickDamage", f = "misc_uncategorized", h = "0x8DEF82AD" },
  { n = "TimerResponse", f = "misc_uncategorized", h = "0xC122D3ED" },
  { n = "TinyGeometryObject", f = "misc_uncategorized", h = "0x06468E56" },
  { n = "TriggerOnTimer", f = "misc_uncategorized", h = "0xFB35CD6F" },
  { n = "Update", f = "misc_uncategorized", h = "0x6E868FFA" },
  { n = "CameraCarPreset", f = "player_vehicle_human", h = "0x5D1F87EF" },
  { n = "CameraShake", f = "player_vehicle_human", h = "0x412D1576" },
  { n = "Carryable", f = "player_vehicle_human", h = "0x712AF756" },
  { n = "EntranceParameters", f = "player_vehicle_human", h = "0x70D05913" },
  { n = "Equipment", f = "player_vehicle_human", h = "0xDAB653E7" },
  { n = "GrappleParameters", f = "player_vehicle_human", h = "0x6AC5EE26" },
  { n = "HumanAnimationSet", f = "player_vehicle_human", h = "0xE8F41716" },
  { n = "HumanAnimationSystem", f = "player_vehicle_human", h = "0x27A3C8A9" },
  { n = "HumanCameraModifier", f = "player_vehicle_human", h = "0x212FFCB2" },
  { n = "HumanInventory", f = "player_vehicle_human", h = "0xE672296C" },
  { n = "ModelMixerProfile", f = "player_vehicle_human", h = "0x1611C502" },
  { n = "RuntimeEntrance", f = "player_vehicle_human", h = "0x55D8D2B1" },
  { n = "RuntimeHeadLookAt", f = "player_vehicle_human", h = "0x6B1666DF" },
  { n = "RuntimeInventory", f = "player_vehicle_human", h = "0xA364FC7D" },
  { n = "RuntimeRiderCrawlExit", f = "player_vehicle_human", h = "0xA7D4D8CA" },
  { n = "RuntimeRiderDiveEnter", f = "player_vehicle_human", h = "0x8A15415F" },
  { n = "RuntimeSeatPlayerUsable", f = "player_vehicle_human", h = "0xE5FB2B37" },
  { n = "RuntimeVehicleCrawlExits", f = "player_vehicle_human", h = "0x1FA43615" },
  { n = "RuntimeVehicleInventory", f = "player_vehicle_human", h = "0x9A6DB283" },
  { n = "SeatParameters", f = "player_vehicle_human", h = "0xA2D3AE72" },
  { n = "Usable", f = "player_vehicle_human", h = "0xB3AF2A59" },
  { n = "VehicleAnimationSet", f = "player_vehicle_human", h = "0x35E09A35" },
  { n = "VehicleDisguiseScale", f = "player_vehicle_human", h = "0x8B3A2B88" },
  { n = "AnimationController", f = "presentation_audio_fx", h = "0xF1D5ADD9" },
  { n = "BlobShadow", f = "presentation_audio_fx", h = "0x40349618" },
  { n = "ColorAnimation", f = "presentation_audio_fx", h = "0x2C9FB394" },
  { n = "EffectAiOccluder", f = "presentation_audio_fx", h = "0x20E89C9D" },
  { n = "EffectTemplate", f = "presentation_audio_fx", h = "0xABAA1F3C" },
  { n = "Flammable", f = "presentation_audio_fx", h = "0xD930020E" },
  { n = "LightAnimation", f = "presentation_audio_fx", h = "0xBD5349F7" },
  { n = "LightObject", f = "presentation_audio_fx", h = "0x97E8EE92" },
  { n = "LocalizedName", f = "presentation_audio_fx", h = "0xA49AFEC1" },
  { n = "MusicRegion", f = "presentation_audio_fx", h = "0x79DCBE56" },
  { n = "MusicSource", f = "presentation_audio_fx", h = "0xB52A3A81" },
  { n = "ObjectHint", f = "presentation_audio_fx", h = "0x2A390A27" },
  { n = "ParticleEmitter", f = "presentation_audio_fx", h = "0xE595AB2F" },
  { n = "RedEffectComponent", f = "presentation_audio_fx", h = "0x60A13E3E" },
  { n = "Ribbon", f = "presentation_audio_fx", h = "0x059B95B9" },
  { n = "RtAlphaAnimation", f = "presentation_audio_fx", h = "0xA7B2F925" },
  { n = "RtColorAnimation", f = "presentation_audio_fx", h = "0x52DA71DE" },
  { n = "RtCoverHint", f = "presentation_audio_fx", h = "0x4350B887" },
  { n = "RtLightAnimation", f = "presentation_audio_fx", h = "0x8AA117BD" },
  { n = "RtRedEffect", f = "presentation_audio_fx", h = "0x9B2DAF6F" },
  { n = "RtRibbon", f = "presentation_audio_fx", h = "0x9AB86EB3" },
  { n = "RtScaleAnimation", f = "presentation_audio_fx", h = "0xC1EDC09B" },
  { n = "RtVFX", f = "presentation_audio_fx", h = "0x757B2069" },
  { n = "RuntimeMusicRegion", f = "presentation_audio_fx", h = "0xAA6964E8" },
  { n = "RuntimeSoundAmbience", f = "presentation_audio_fx", h = "0x5FE773CC" },
  { n = "RuntimeSoundEffect", f = "presentation_audio_fx", h = "0x0E83BCB7" },
  { n = "RuntimeSoundRuinKey", f = "presentation_audio_fx", h = "0x25E2DEF3" },
  { n = "ScaleAnimation", f = "presentation_audio_fx", h = "0x60E3D029" },
  { n = "SoundAmbience", f = "presentation_audio_fx", h = "0x514CAD3A" },
  { n = "SoundEffect", f = "presentation_audio_fx", h = "0xB40954F5" },
  { n = "SoundInterior", f = "presentation_audio_fx", h = "0x05D1D9BA" },
  { n = "SoundRuinKey", f = "presentation_audio_fx", h = "0xBC1F685D" },
  { n = "Status", f = "presentation_audio_fx", h = "0x09CD8B1F" },
  { n = "TerrainFade", f = "presentation_audio_fx", h = "0x26AE8736" },
  { n = "WpMeshShape", f = "render_asset_pipeline", h = "0x509EEE8A" },
  { n = "display", f = "render_asset_pipeline", h = "0x84D0382D" },
  { n = "failresolve", f = "render_asset_pipeline", h = "0x213E70C3" },
  { n = "finalize", f = "render_asset_pipeline", h = "0x3E6C2A4F" },
  { n = "index", f = "render_asset_pipeline", h = "0xBCC8D613" },
  { n = "potential", f = "render_asset_pipeline", h = "0x8BCA940D" },
  { n = "pshader", f = "render_asset_pipeline", h = "0x8219BA20" },
  { n = "surface", f = "render_asset_pipeline", h = "0xBE609AE2" },
  { n = "texture", f = "render_asset_pipeline", h = "0xF011157A" },
  { n = "vertdecl", f = "render_asset_pipeline", h = "0xDC4B0E40" },
  { n = "vertex", f = "render_asset_pipeline", h = "0x0C4C02F7" },
  { n = "vshader", f = "render_asset_pipeline", h = "0x504BE9D2" },
  { n = "BoundaryData", f = "world_terrain_roads_streaming", h = "0x5A59763F" },
  { n = "CircleRegion", f = "world_terrain_roads_streaming", h = "0x6691B221" },
  { n = "IntersectionToIntersection", f = "world_terrain_roads_streaming", h = "0xEB6DE962" },
  { n = "LaneData", f = "world_terrain_roads_streaming", h = "0x6A08E327" },
  { n = "LaneZeroDirection", f = "world_terrain_roads_streaming", h = "0x7CF73564" },
  { n = "LineRegion", f = "world_terrain_roads_streaming", h = "0x6310807F" },
  { n = "LowResTerrainObject", f = "world_terrain_roads_streaming", h = "0x2D8D2435" },
  { n = "Model", f = "world_terrain_roads_streaming", h = "0x5B724250" },
  { n = "ObjectMaterial", f = "world_terrain_roads_streaming", h = "0xC1F1F72F" },
  { n = "PathData", f = "world_terrain_roads_streaming", h = "0xAEF6F7B4" },
  { n = "PointLocation", f = "world_terrain_roads_streaming", h = "0x60B7ABE0" },
  { n = "RoadIntersection", f = "world_terrain_roads_streaming", h = "0x6FD048F4" },
  { n = "RtFlowControl", f = "world_terrain_roads_streaming", h = "0xB6CB89DE" },
  { n = "RtFlowCycleTimer", f = "world_terrain_roads_streaming", h = "0xD4CA71DA" },
  { n = "RtGenericLOD", f = "world_terrain_roads_streaming", h = "0x0C51B633" },
  { n = "RtGenericLODProxy", f = "world_terrain_roads_streaming", h = "0xCE91973D" },
  { n = "RtRoadIntersection", f = "world_terrain_roads_streaming", h = "0x5E137672" },
  { n = "RtSpeedLimit", f = "world_terrain_roads_streaming", h = "0xFF142695" },
  { n = "RtTerrainChildren", f = "world_terrain_roads_streaming", h = "0x0FF1C703" },
  { n = "RtTickDamage", f = "world_terrain_roads_streaming", h = "0x27E19BF7" },
  { n = "RuntimeLayerId", f = "world_terrain_roads_streaming", h = "0x2284FE19" },
  { n = "SceneObject", f = "world_terrain_roads_streaming", h = "0xB6185886" },
  { n = "SpawnerAdjust", f = "world_terrain_roads_streaming", h = "0x1003413E" },
  { n = "SpeedLimit", f = "world_terrain_roads_streaming", h = "0x9ADD960B" },
  { n = "SphereRegion", f = "world_terrain_roads_streaming", h = "0x4CA3FD52" },
  { n = "SysPathIntersectionIndex", f = "world_terrain_roads_streaming", h = "0x2EEF9DD2" },
  { n = "SysPathRoadIndex", f = "world_terrain_roads_streaming", h = "0x805AD569" },
  { n = "TerrainGuidMappingHighResToLowRe", f = "world_terrain_roads_streaming", h = "0xD5913141" },
  { n = "TerrainKey", f = "world_terrain_roads_streaming", h = "0x0868B0CD" },
  { n = "TerrainObject", f = "world_terrain_roads_streaming", h = "0x6C82EBE5" },
}
-- 232 classes across 9 families

-- index by lowercased name, computed once
local BY_NAME = {}
for _, c in ipairs(CLASSES) do BY_NAME[c.n:lower()] = c end

function Ess.Ecs.classes() return CLASSES end

function Ess.Ecs.get(name)
    if type(name) ~= "string" then return nil end
    return BY_NAME[name:lower()]
end

function Ess.Ecs.hash(name)
    local c = Ess.Ecs.get(name)
    return c and c.h or nil
end

function Ess.Ecs.family(name)
    local c = Ess.Ecs.get(name)
    return c and c.f or nil
end

function Ess.Ecs.families()
    local seen, out = {}, {}
    for _, c in ipairs(CLASSES) do
        if not seen[c.f] then seen[c.f] = true; out[#out + 1] = c.f end
    end
    table.sort(out)
    return out
end

function Ess.Ecs.find(query)
    if type(query) ~= "string" then return {} end
    local q = query:lower()
    local out = {}
    for _, c in ipairs(CLASSES) do
        if c.n:lower():find(q, 1, true) or c.f:lower():find(q, 1, true) then out[#out + 1] = c end
    end
    return out
end
