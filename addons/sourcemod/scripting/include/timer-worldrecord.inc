#if defined _timer_worldrecord_included
 #endinput
#endif
#define _timer_worldrecord_included

native Timer_ForceReloadCache();

public SharedPlugin:__pl_timer_worldrecord = 
{
	name = "timer-worldrecord",
	file = "timer-worldrecord.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

public __pl_timer_worldrec_SetNTVOpt()
{
	MarkNativeAsOptional("Timer_ForceReloadCache");
}