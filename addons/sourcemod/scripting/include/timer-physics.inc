#if defined _timer_physics_included
 #endinput
#endif
#define _timer_physics_included

native Timer_GetScripter(client);

native Timer_GetPickedMode(client);

native Timer_GetForceMode();

native Timer_ApplyPhysics(client);

native Timer_GetJumpAccuracy(client, &Float:percent);
native Timer_GetCurrentSpeed(client, &Float:speed);
native Timer_GetMaxSpeed(client, &Float:maxspeed);
native Timer_GetAvgSpeed(client, &Float:avgspeed);

native Timer_ResetAccuracy(client);

public SharedPlugin:__pl_timer_physics = 
{
	name = "timer-physics",
	file = "timer-physics.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};