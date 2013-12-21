#pragma semicolon 1

#include <sourcemod>
#include <adminmenu>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#include <timer>
#include <timer-config_loader.sp>

new Handle:g_hFPSMaxDisable = INVALID_HANDLE;
new bool:g_bFPSMaxDisable = false;

public Plugin:myinfo =
{
    name        = "[Timer] FPSCheck",
    author      = "Zipcore",
    description = "fps_max check component for [Timer]",
    version     = PL_VERSION,
    url         = "zipcore#googlemail.com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-fpscheck");

	return APLRes_Success;
}

public OnPluginStart()
{
	g_hFPSMaxDisable = CreateConVar("timer_fpsmax_violation_disable", "0", "Don't switch to FPSMAX style.");
	HookConVarChange(g_hFPSMaxDisable, Action_OnSettingsChange);
	g_bFPSMaxDisable = GetConVarBool(g_hFPSMaxDisable);
	LoadPhysics();
	LoadTimerSettings();
}

public OnMapStart()
{
	LoadPhysics();
	LoadTimerSettings();
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_hFPSMaxDisable)
		g_bFPSMaxDisable = bool:StringToInt(newvalue);	
}

public OnTimerStarted(client)
{
	//Check for wrong mode
	if(g_Physics[Timer_GetMode(client)][ModeFPSMax])
	{
		CreateTimer(1.0, FPSCheck, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:FPSCheck(Handle:timer, any:client)
{
	if(g_bFPSMaxDisable) 
		return Plugin_Stop;

	if(IsFakeClient(client))
		return Plugin_Stop;

	new bool:enabled;
	new jumps;
	new Float:time;
	new fpsmax;

	if (Timer_GetClientTimer(client, enabled, time, jumps, fpsmax))
	{
		if(fpsmax < 300 && fpsmax != 0 && g_ModeDefault != -1)
		{
			//change mode
			Timer_SetMode(client, g_ModeDefault);
			Timer_Restart(client);
			
			decl String:warnstr[128];
			Format(warnstr, sizeof(warnstr), "%T", "Custom FPS", client);
			PrintToChat(client, PLUGIN_PREFIX, "Custom FPS");
		}
	}
	return Plugin_Stop;
}