#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <timer>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#define REQUIRE_EXTENSIONS

//this variable defines how many checkpoints per player there will be
#define CPLIMIT 10

//this variable defines who is allowed to execute admin commands
#define ADMIN_LEVEL ADMFLAG_UNBAN

//-----------------------------//
// nothing to change over here //
//-----------------------------//
//...
#define VERSION "2.1.0"

#define YELLOW 0x01
#define TEAMCOLOR 0x02

#define LIGHTGREEN 0x03
#define GREEN 0x04

#define POS_START 0
#define POS_STOP 1

#define RECORD_TIME 0
#define RECORD_JUMP 1

#define MYSQL 0
#define SQLITE 1

#define MAX_MAP_LENGTH 32

//-------------------//
// many variables :) //
//-------------------//
new g_DbType;
new Handle:g_hDb = INVALID_HANDLE;

new Handle:g_hcvarEnable = INVALID_HANDLE;
new bool:g_bEnabled = false;

new Handle:g_hcvarRestore = INVALID_HANDLE;
new bool:g_bRestore = false;

new Float:g_fPlayerCords[MAXPLAYERS+1][CPLIMIT][3];
new Float:g_fPlayerAngles[MAXPLAYERS+1][CPLIMIT][3];

//number of current checkpoint in the storage array
new g_CurrentCp[MAXPLAYERS+1];
//amount of checkpoints available
new g_WholeCp[MAXPLAYERS+1];
new String:g_szMapName[MAX_MAP_LENGTH];

new g_BeamSpriteRing1, g_BeamSpriteRing2;


//----------//
// includes //
//----------//
#include "cPMod/admin.sp"
#include "cPMod/commands.sp"
#include "cPMod/helper.sp"
#include "cPMod/sql.sp"


public Plugin:myinfo = {
	name = "cPMod",
	author = "byaaaaah",
	description = "Bunnyhop / Surf / Tricks server modification",
	version = VERSION,
	url = "http://b-com.tk"
}

//----------------//
// initialization //
//----------------//
public OnPluginStart(){
	LoadTranslations("cpmod.phrases");
	
	db_setupDatabase();
	CreateConVar("cPMod_version", VERSION, "cP Mod version.", FCVAR_DONTRECORD|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hcvarEnable     = CreateConVar("sm_cp_enabled", "1", "Enable/Disable the plugin.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_bEnabled      = GetConVarBool(g_hcvarEnable);
	HookConVarChange(g_hcvarEnable, OnSettingChanged);

	g_hcvarRestore    = CreateConVar("sm_cp_restore", "1", "Enable/Disable automatic saving of checkpoints to database.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bRestore        = GetConVarBool(g_hcvarRestore);
	HookConVarChange(g_hcvarRestore, OnSettingChanged);
	
	RegConsoleCmd("sm_nextcp", Client_Next, "Next checkpoint");
	RegConsoleCmd("sm_prevcp", Client_Prev, "Previous checkpoint");
	RegConsoleCmd("sm_save", Client_Save, "Saves a checkpoint");
	RegConsoleCmd("sm_tele", Client_Tele, "Teleports you to last checkpoint");
	RegConsoleCmd("sm_cp", Client_Cp, "Opens teleportmenu");
	RegConsoleCmd("sm_clear", Client_Clear, "Erases all checkpoints");
	RegConsoleCmd("sm_cphelp", Client_Help, "Displays the help menu");
	
	RegAdminCmd("sm_resetcheckpoints", Admin_ResetCheckpoints, ADMIN_LEVEL, "Resets all checkpoints for given player with / without given map.");
	
	AutoExecConfig(true, "sm_cpmod");
}

//--------------------------//
// executed on start of map //
//--------------------------//
public OnMapStart()
{
	//precache some files
	g_BeamSpriteRing1 = PrecacheModel("materials/sprites/tp_beam001.vmt");
	g_BeamSpriteRing2 = PrecacheModel("materials/sprites/crystal_beam1.vmt");
	PrecacheSound("buttons/blip1.wav", true);
	
	GetCurrentMap(g_szMapName, MAX_MAP_LENGTH);
}

//------------------------//
// executed on end of map //
//------------------------//
public OnMapEnd(){
	new max = GetMaxClients();
	//for all of the players
	for(new i = 0; i <= max; i++){
		//if client valid
		if(i != 0 && IsClientInGame(i) && !IsFakeClient(i) && IsClientConnected(i)){
			new current = g_CurrentCp[i];
			//if checkpoint restoring and valid checkpoint
			if(g_bRestore && current != -1){
				//update the checkpoint in the database
				db_updatePlayerCheckpoint(i, current);
			}
		}
	}
}

//-----------------------------------//
// hook executed on changed settings //
//-----------------------------------//
public OnSettingChanged(Handle:convar, const String:oldValue[], const String:newValue[]){
	if(convar == g_hcvarEnable){
		if(newValue[0] == '1')
			g_bEnabled = true;
		else
			g_bEnabled = false;
	}
	else if(convar == g_hcvarRestore)
	{
		if(newValue[0] == '1')
			g_bRestore = true;
		else
			g_bRestore = false;
	}
}

//------------------------------------//
// executed on client post admincheck //
//------------------------------------//
public OnClientPostAdminCheck(client)
{
	//if g_Enabled and client valid
	if(IsClientInGame(client) && !IsFakeClient(client))
	{
		if(g_bEnabled)
		{
			//reset some settings
			g_CurrentCp[client] = -1;
			g_WholeCp[client] = 0;
		
			//if checkpoint restoring select the last one
			if(g_bRestore)
				db_selectPlayerCheckpoint(client);
		}
	}
}

//-------------------------------//
// executed on player disconnect //
//-------------------------------//
public OnClientDisconnect(client)
{
	if(g_bEnabled){
		new current = g_CurrentCp[client];
		//if checkpoint restoring and valid checkpoint
		if(g_bRestore && current != -1){
			//update the checkpoint in the database
			db_updatePlayerCheckpoint(client, current);
		}
	}
}

public OnTimerStarted(client)
{
	if(StrContains(g_szMapName,"xc_",false) == 0)
	{
		//if no valid player
		if(!IsPlayerAlive(client) || GetClientTeam(client) == 1)
			return;

		//if plugin is enabled
		if(g_bEnabled){
			//reset counters
			g_CurrentCp[client] = -1;
			g_WholeCp[client] = 0;
		}
	} 
}