#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#include <timer>
#include <timer-physics>
#include <timer-teams>
#include <timer-logging>
#include <timer-config_loader.sp>

new String:g_currentMap[64];

new bool:g_bClientChallenge[MAXPLAYERS+1];
new g_iChallengeCountdown[MAXPLAYERS+1];

new bool:g_bClientCoop[MAXPLAYERS+1];
new g_iCoopCountdown[MAXPLAYERS+1];

new Handle:Sound_ChallengeStart = INVALID_HANDLE;
new String:SND_CHALLENGE_START[MAX_FILE_LEN];
new Handle:Sound_TimerOwned = INVALID_HANDLE;
new String:SND_TIMER_OWNED[MAX_FILE_LEN];

new Handle:g_OnChallengeStart;
new Handle:g_OnChallengeConfirm;
new Handle:g_OnChallengeWin;
new Handle:g_OnChallengeForceEnd;

new Handle:g_OnCoopStart;
new Handle:g_OnCoopConfirm;
new Handle:g_OnCoopWin;
new Handle:g_OnCoopForceEnd;

public Plugin:myinfo =
{
    name        = "[Timer] Teams",
    author      = "Zipcore, Jason Bourne",
    description = "Challenge mode for [Timer]",
    version     = PL_VERSION,
    url         = "zipcore#googlemail.com, jason@immersion-networks.com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-teams");
	CreateNative("Timer_GetChallengeStatus", Native_GetChallengeStatus);
	CreateNative("Timer_GetCoopStatus", Native_GetCoopStatus);
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadPhysics();
	LoadTimerSettings();
	
	LoadTranslations("timer.phrases");

	if(g_Settings[ChallengeEnable]) RegConsoleCmd("sm_challenge", Command_Challenge);
	if(g_Settings[CoopEnable]) RegConsoleCmd("sm_coop", Command_Coop);

	Sound_ChallengeStart = CreateConVar("timer_sound_challenge_start", "ui/freeze_cam.wav", "");
	Sound_TimerOwned = CreateConVar("timer_sound_owned", "ui/freeze_cam.wav", "");
	
	HookConVarChange(Sound_ChallengeStart, Action_OnSettingsChange);
	HookConVarChange(Sound_TimerOwned, Action_OnSettingsChange);

	g_OnChallengeConfirm = CreateGlobalForward("OnChallengeConfirm", ET_Event, Param_Cell,Param_Cell,Param_Cell);
	g_OnChallengeStart = CreateGlobalForward("OnChallengeStart", ET_Event, Param_Cell,Param_Cell);
	g_OnChallengeWin = CreateGlobalForward("OnChallengeWin", ET_Event, Param_Cell,Param_Cell);
	g_OnChallengeForceEnd = CreateGlobalForward("OnChallengeForceEnd", ET_Event, Param_Cell,Param_Cell);
	
	g_OnCoopConfirm = CreateGlobalForward("OnCoopConfirm", ET_Event, Param_Cell,Param_Cell,Param_Cell);
	g_OnCoopStart = CreateGlobalForward("OnCoopStart", ET_Event, Param_Cell,Param_Cell);
	g_OnCoopWin = CreateGlobalForward("OnCoopWin", ET_Event, Param_Cell,Param_Cell);
	g_OnCoopForceEnd = CreateGlobalForward("OnCoopForceEnd", ET_Event, Param_Cell,Param_Cell);
	
	AutoExecConfig(true, "timer/timer-teams");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public OnMapStart()
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	
	LoadPhysics();
	LoadTimerSettings();
}

public OnConfigsExecuted()
{
	CacheSounds();
}

public CacheSounds()
{
	GetConVarString(Sound_ChallengeStart, SND_CHALLENGE_START, sizeof(SND_CHALLENGE_START));
	PrepareSound(SND_CHALLENGE_START);
	
	GetConVarString(Sound_TimerOwned, SND_TIMER_OWNED, sizeof(SND_TIMER_OWNED));
	PrepareSound(SND_TIMER_OWNED);
}

public PrepareSound(String: sound[MAX_FILE_LEN])
{
	decl String:fileSound[MAX_FILE_LEN];

	Format(fileSound, MAX_FILE_LEN, "sound/%s", sound);

	if (FileExists(fileSound))
	{
		PrecacheSound(sound, true);
		AddFileToDownloadsTable(fileSound);
	}
	else
	{
		PrintToServer("[Timer] ERROR: File '%s' not found!", fileSound);
	}
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == Sound_ChallengeStart)
		Format(SND_CHALLENGE_START, sizeof(SND_CHALLENGE_START) ,"%s", newvalue);
	else if (cvar == Sound_TimerOwned)
		Format(SND_TIMER_OWNED, sizeof(SND_TIMER_OWNED) ,"%s", newvalue);
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_bClientChallenge[client] = false;
	g_bClientCoop[client] = false;
}

public OnClientStartTouchZoneType(client, MapZoneType:type)
{
	if(client != 0)
	{
		if (type == ZtEnd)
		{
			new mate = Timer_GetClientTeammate(client);
			
			if(mate == 0)
				return;
			
			if(g_bClientChallenge[client]) EndChallenge(client,0);
			else if (g_bClientCoop[client] && Timer_IsPlayerTouchingZoneType(mate, ZtEnd)) EndCoop(client,0);
		}
	}
}

public OnClientEndTouchZoneType(client, MapZoneType:type)
{
	if(client != 0)
	{
		if (type == ZtStart)
		{
			if(g_Settings[CoopOnly])
			{
				new mate = Timer_GetClientTeammate(client);
				
				if(mate == 0 && !g_bClientCoop[client])
				{
					FakeClientCommand(client, "sm_restart");
					PrintToChat(client, "%s Type !coop and choose your teammate to become ranked.", PLUGIN_PREFIX2);
				}
			}
		}
	}
}

public Action:Command_Challenge(client, args)
{
	new points = Timer_GetPoints(client);
	
	if(points > 0)
	{
		new Handle:menu = CreateMenu(MenuHandlerChallenge);
		SetMenuTitle(menu, "Select your opponent");
		
		new iCount = 0;
		
		for (new i = 1; i <= GetMaxClients(); i++)
		{
			if(!Client_IsValid(i))
			{
				continue;
			}
			if(IsFakeClient(i))
			{
				continue;
			}
			if(client == i)
			{
				continue;
			}
			if(g_bClientCoop[i])
			{
				continue;
			}
			if(g_bClientChallenge[i])
			{
				continue;
			}
			if(Timer_GetPoints(i) <= 0)
			{
				continue;
			}
			if(IsFakeClient(i))
			{
				continue;
			}
			
			new String:name2[32];
			Format(name2, sizeof(name2), "%N", i);
			new String:zone2[32];
			Format(zone2,sizeof(zone2),"%d", i);
			AddMenuItem(menu, zone2, name2);
			
			iCount++;
		}
	
		if(iCount == 0)
		{
			PrintToChat(client, PLUGIN_PREFIX, "No Target");
			return Plugin_Handled;
		}
		
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, 20);
	}
	else CPrintToChat(client, "%s You need points to challenge someone.", PLUGIN_PREFIX2);
     
	return Plugin_Handled;
}

public MenuHandlerChallenge(Handle:menu, MenuAction:action, creator, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:info[100], String:info2[100];
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info), _, info2, sizeof(info2));
		new client = StringToInt(info);
		if(found)
		{
			if(IsClientInGame(client))
			{
				new Handle:menu2 = CreateMenu(MenuHandlerChallengeConfirm);
				SetMenuTitle(menu2, "Confirm Challenge with %N on mode: %s.", creator, g_Physics[Timer_GetMode(creator)][ModeName]);
			
				new String:name[32];
				Format(name, sizeof(name),"%d", creator);
				AddMenuItem(menu2, name, "Yes");
				AddMenuItem(menu2, "no", "no");
			
				SetMenuExitButton(menu, true);
				DisplayMenu(menu2, client, 20);
			}
		}
	}
}

public MenuHandlerChallengeConfirm(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:info[100], String:info2[100];
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info), _, info2, sizeof(info2));
		new target = StringToInt(info);
		if(StrEqual(info, "no"))
		{
			
		}
		else if(found)
		{	
			if(!target || target <= 0)
			{
			}
			else
			{
				StartChallenge(client, target);
				
				CPrintToChatAll("%s %N has confirmed a challenge with %N.", PLUGIN_PREFIX2, client, target);
				
				Call_StartForward(g_OnChallengeConfirm);
				Call_PushCell(client);
				Call_PushCell(target);
				Call_PushCell(found);
				Call_Finish();
			}
		}
	}
}

StartChallenge(client, target)
{
	Timer_SetClientTeammate(client, target, 1);
	Timer_SetMode(client, Timer_GetMode(target));
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	SetEntityMoveType(target, MOVETYPE_NONE);
	
	Timer_SetClientHide(client, 1);
	Timer_SetClientHide(target, 1);
	
	g_iChallengeCountdown[client] = 5;
	g_iChallengeCountdown[target] = 5;
	
	Timer_SetBonus(client, 0);
	Timer_SetBonus(target, 0);
	
	g_bClientChallenge[client] = false;
	g_bClientChallenge[target] = false;

	CreateTimer(1.0, ChallengeCountdown, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, ChallengeCountdown, target, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action:ChallengeCountdown(Handle:timer, any:client)
{
	if(!IsClientInGame(client))
		return Plugin_Stop;
	
	PrintCenterText(client, "%d", g_iChallengeCountdown[client]);
	
	g_iChallengeCountdown[client]--;
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	//Timer_SetIgnoreEndTouchStart(client, 1);
	
	if(g_iChallengeCountdown[client] <= 0)
	{
		PrintCenterText(client, "GO GO GO !!!");
		EmitSoundToClient(client, SND_CHALLENGE_START);
		SetEntityMoveType(client, MOVETYPE_WALK);
		new mate = Timer_GetClientTeammate(client);
		
		g_bClientChallenge[client] = true;
		g_bClientChallenge[mate] = true;
		
		Call_StartForward(g_OnChallengeStart);
		Call_PushCell(client);
		Call_PushCell(mate);
		Call_Finish();
		
		Timer_Start(client);
		Timer_Start(mate);
		
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action:Command_Coop(client, args)
{
	new Handle:menu = CreateMenu(MenuHandlerCoop);
	SetMenuTitle(menu, "Teammate Select");
	//new bool:isadmin = Client_IsAdmin(client);
	
	new iCount = 0;
	
	//show rest
	for (new i = 1; i <= GetMaxClients(); i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}
		if(client == i)
		{
			continue;
		}
		if(g_bClientCoop[i])
		{
			continue;
		}
		if(g_bClientChallenge[i])
		{
			continue;
		}
		
		new String:name2[32];
		Format(name2, sizeof(name2), "%N", i);
		new String:zone2[32];
		Format(zone2,sizeof(zone2),"%d", i);
		AddMenuItem(menu, zone2, name2);
		
		iCount++;
	}
	
	if(iCount == 0)
	{
		PrintToChat(client, PLUGIN_PREFIX, "No Target");
		return Plugin_Handled;
	}
	
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 20);
     
	return Plugin_Handled;
}

public MenuHandlerCoop(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:info[100], String:info2[100];
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info), _, info2, sizeof(info2));
		new target = StringToInt(info);
		if(found)
		{
			if(IsClientInGame(target))
			{
				if(IsFakeClient(target))
				{
					StartCoop(client, target);
				}
				else
				{
					new Handle:menu2 = CreateMenu(MenuHandlerCoopConfirm);
					SetMenuTitle(menu2, "Confirm Coop-Modus with %N", client);
					//new bool:isadmin = Client_IsAdmin(client);
				
					new String:xclient[32];
					Format(xclient, sizeof(xclient),"%d", client);
					AddMenuItem(menu2, xclient, "Yes");
					AddMenuItem(menu2, "no", "no");
				
					SetMenuExitButton(menu, true);
					DisplayMenu(menu2, target, 20);
				}
			}
		}
	}
}

public MenuHandlerCoopConfirm(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:info[100], String:info2[100];
		new bool:found = GetMenuItem(menu, param2, info, sizeof(info), _, info2, sizeof(info2));
		new target = StringToInt(info);
		if(StrEqual(info, "no"))
		{
			
		}
		else if(found)
		{	
			if(!target || target <= 0)
			{
			}
			else
			{
				StartCoop(client, target);
			}
		}
		
		Call_StartForward(g_OnCoopConfirm);
		Call_PushCell(client);
		Call_PushCell(target);
		Call_PushCell(found);
		Call_Finish();
	}
}

StartCoop(client, target)
{
	Timer_SetClientTeammate(client, target, 1);
	Timer_SetMode(client, Timer_GetMode(target));
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	SetEntityMoveType(target, MOVETYPE_NONE);
	
	g_iCoopCountdown[client] = 5;
	g_iCoopCountdown[target] = 5;
	
	Timer_SetBonus(client, 0);
	Timer_SetBonus(target, 0);
	
	g_bClientCoop[client] = false;
	g_bClientCoop[target] = false;

	CreateTimer(1.0, CoopCountdown, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, CoopCountdown, target, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action:CoopCountdown(Handle:timer, any:client)
{
	if(!IsClientInGame(client))
		return Plugin_Stop;
	
	PrintCenterText(client, "%d", g_iCoopCountdown[client]);
	
	g_iCoopCountdown[client]--;
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	if(g_iCoopCountdown[client] <= 0)
	{
		PrintCenterText(client, "GO GO GO !!!");
		SetEntityMoveType(client, MOVETYPE_WALK);
		new mate = Timer_GetClientTeammate(client);
		
		g_bClientCoop[client] = true;
		g_bClientCoop[mate] = true;
		
		Call_StartForward(g_OnCoopStart);
		Call_PushCell(client);
		Call_PushCell(mate);
		Call_Finish();
		
		Timer_Start(client);
		Timer_Start(mate);
		
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action:EndChallenge(client,force)
{
	new mate = Timer_GetClientTeammate(client);
	
	if(g_bClientChallenge[client] && g_bClientChallenge[mate])
	{
		//Failed?
		if (force == 1)
		{
			Call_StartForward(g_OnChallengeForceEnd);
			Call_PushCell(client);
			Call_PushCell(mate);
			Call_Finish();
			EndChallenge(mate,2);
		}
		//We have a winner
		else
		{
			new String:pname[32], String:pname2[32];	
			
			Format(pname, sizeof(pname), "%N", client);
			Format(pname2, sizeof(pname2), "%N", mate);
			
			new bool:enabled; //tier running
			new jumps; //current jump count
			new fpsmax; //fps settings
			new bool:bonus = false; //bonus timer running
			new Float:time; //current time
			
			new mode = Timer_GetMode(client);
			
			Timer_GetClientTimer(client, enabled, time, jumps, fpsmax);
			
			//This is our winner
			if (force == 0) 
			{
				//Calculate points
				
				//Print info
				CPrintToChatAll("%s %N has beaten %N.", PLUGIN_PREFIX2, client, mate);
				
				//Play sounds
				EmitSoundToClient(client, SND_TIMER_OWNED);
				EmitSoundToClient(mate, SND_TIMER_OWNED);
				
				//Reset hide
				Timer_SetClientHide(client, 0);
				Timer_SetClientHide(mate, 0);
				
				//Record winner
				Timer_FinishRound(client, g_currentMap, time, jumps, mode, fpsmax, bonus);
				
				//Forward
				Call_StartForward(g_OnChallengeWin);
				Call_PushCell(client);
				Call_PushCell(mate);
				Call_Finish();
				
				//Fake death event
				new Handle:event = CreateEvent("player_death");
				if (event != INVALID_HANDLE)
				{
					SetEventInt(event, "userid", GetClientUserId(mate));
					SetEventInt(event, "attacker", GetClientUserId(client));
					SetEventString(event, "weapon", "weapon_Challenge");
					FireEvent(event, false);
				}
			}
		}
	}
	
	//end challenge
	g_bClientChallenge[client] = false;
	g_bClientChallenge[mate] = false;
	
	
	//reset challenge
	Timer_Reset(client);
	Timer_Reset(mate);
	
	//dissolve team
	Timer_SetClientTeammate(client, 0, 0);
	Timer_SetClientTeammate(mate, 0, 0);
}

public Action:EndCoop(client, force)
{
	new mate = Timer_GetClientTeammate(client);
	
	if(g_bClientCoop[client] && g_bClientCoop[mate])
	{
		new String:pname[32], String:pname2[32];	
			
		Format(pname, sizeof(pname), "%N", client);
		Format(pname2, sizeof(pname2), "%N", mate);
			
		if (force == 1)
		{
			PrintToChatAll(PLUGIN_PREFIX, "Coop Fail", pname, pname2);
			
			Call_StartForward(g_OnCoopForceEnd);
			Call_PushCell(client);
			Call_PushCell(mate);
			Call_Finish();
		}
		else if (force == 0)
		{
			PrintToChatAll(PLUGIN_PREFIX, "Coop Win", pname, pname2);
			
			Call_StartForward(g_OnCoopWin);
			Call_PushCell(client);
			Call_PushCell(mate);
			Call_Finish();
			
			new bool:enabled; //tier running
			new jumps; //current jump count
			new fpsmax; //fps settings
			new bool:bonus = false; //bonus timer running
			new Float:time; //current time
			
			new mode = Timer_GetMode(client);
			
			Timer_GetClientTimer(client, enabled, time, jumps, fpsmax);
			
			Timer_FinishRound(client, g_currentMap, time, jumps, mode, fpsmax, bonus);
			Timer_FinishRound(mate, g_currentMap, time, jumps, mode, fpsmax, bonus);
		}
	}
	
	g_bClientCoop[client] = false;
	g_bClientCoop[mate] = false;
	
	Timer_Reset(client);
	Timer_Reset(mate);
	
	Timer_SetClientTeammate(client, 0, 0);
	Timer_SetClientTeammate(mate, 0, 0);
}

public OnTimerStopped(client)
{
	ForceEnd(client);
}

public OnTimerRestart(client)
{
	ForceEnd(client);
}

public OnTimerPaused(client)
{
	ForceEnd(client);
}

ForceEnd(client)
{
	new mate = Timer_GetClientTeammate(client);
	
	if(g_Settings[CoopOnly] && mate == 0)
	{
		CreateTimer(0.0, Reset, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	if(mate != 0)
	{
		if(g_bClientChallenge[client])	
		{
			EndChallenge(client,1);
		}
		else if (g_bClientCoop[client])
		{
			EndCoop(client,1);
		}
	}
}

public Action:Reset(Handle:timer, any:client)
{
	Timer_Reset(client);
	return Plugin_Stop;
}

public Native_GetChallengeStatus(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(g_bClientChallenge[client]) return 1;
	else return 0;
}

public Native_GetCoopStatus(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if(g_bClientCoop[client]) return 1;
	else return 0;
}