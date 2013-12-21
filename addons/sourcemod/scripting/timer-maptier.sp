#pragma semicolon 1

#include <sourcemod>

#include <timer>
#include <timer-logging>

#undef REQUIRE_PLUGIN
#include <timer-physics>

new Handle:g_hSQL;

new String:g_currentMap[32];
new g_reconnectCounter = 0;

new g_maptier = 0;
new g_stagecount = 0;

public Plugin:myinfo =
{
    name        = "[Timer] Map Tier System",
    author      = "Zipcore",
    description = "World Record component for [Timer]",
    version     = PL_VERSION,
    url         = "zipcore#googlemail.com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-maptier");
	
	CreateNative("Timer_GetTier", Native_GetMapTier);
	CreateNative("Timer_SetTier", Native_SetMapTier);
	
	CreateNative("Timer_GetStageCount", Native_GetStageCount);
	CreateNative("Timer_SetStageCount", Native_SetStageCount);

	return APLRes_Success;
}

public OnPluginStart()
{
	ConnectSQL();
	
	LoadTranslations("timer.phrases");
	
	RegAdminCmd("sm_maptier", Command_MapTier, ADMFLAG_RCON, "sm_maptier");
	RegAdminCmd("sm_stagecount", Command_StageCount, ADMFLAG_RCON, "sm_stagecount");
	
	AutoExecConfig(true, "timer-maptier");
}

public OnMapStart()
{
	ConnectSQL();
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	g_maptier = 0;
	if (g_hSQL != INVALID_HANDLE) LoadMapTier();
}

ConnectSQL()
{
    if (g_hSQL != INVALID_HANDLE)
        CloseHandle(g_hSQL);
	
    g_hSQL = INVALID_HANDLE;

    if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer");
	}
    else
	{
		Timer_LogError("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_reconnectCounter >= 5)
	{
		Timer_LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("Connection to SQL database has failed, Reason: %s", error);
		
		g_reconnectCounter++;
		ConnectSQL();
		
		return;
	}

	decl String:driver[16];
	SQL_GetDriverIdent(owner, driver, sizeof(driver));

	g_hSQL = CloneHandle(hndl);
	
	if (StrEqual(driver, "mysql", false))
	{
		SQL_FastQuery(hndl, "SET NAMES  'utf8'");
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `maptier` (`id` int(11) NOT NULL AUTO_INCREMENT, `map` varchar(32) NOT NULL, `tier` int(11) NOT NULL, `stagecount` int(11) NOT NULL, PRIMARY KEY (`id`));");
	}
		
	g_reconnectCounter = 1;
}

public CreateSQLTableCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (owner == INVALID_HANDLE)
	{
		Timer_LogError(error);

		g_reconnectCounter++;
		ConnectSQL();
		
		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on CreateSQLTable: %s", error);
		return;
	}
	
	LoadMapTier();
}

LoadMapTier()
{
	if (g_hSQL != INVALID_HANDLE)
	{
		decl String:query[128];
		Format(query, sizeof(query), "SELECT tier,stagecount FROM maptier WHERE map = '%s';", g_currentMap);
		SQL_TQuery(g_hSQL, LoadTierCallback, query, _, DBPrio_Normal);   
	}
}	

public LoadTierCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on LoadTier: %s", error);
		return;
	}
	
	while (SQL_FetchRow(hndl))
	{
		g_maptier = SQL_FetchInt(hndl, 0);
		g_stagecount = SQL_FetchInt(hndl, 1);
	}
	
	CreateTimer(1.0, Timer_InsertMapTier, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_InsertMapTier(Handle:timer)
{
	if(g_maptier == 0)
	{
		decl String:query[128];
		Format(query, sizeof(query), "INSERT INTO maptier (map, tier) VALUES ('%s','1');", g_currentMap);

		SQL_TQuery(g_hSQL, InsertTierCallback, query, _, DBPrio_Normal);
	}
	
	return Plugin_Stop;
}

public InsertTierCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on InsertTier: %s", error);
		return;
	}
	
	LoadMapTier();
}

public Action:Command_MapTier(client, args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_maptier [tier]");
		return Plugin_Handled;	
	}
	else if (args == 1)
	{
		decl String:tier[64];
		GetCmdArg(1,tier,sizeof(tier));
		Timer_SetTier(StringToInt(tier));	
	}
	return Plugin_Handled;	
}

public Action:Command_StageCount(client, args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_stagecount [stagecount]");
		return Plugin_Handled;	
	}
	else if(args == 1)
	{
		decl String:stagecount[64];
		GetCmdArg(1,stagecount,sizeof(stagecount));
		Timer_SetStageCount(StringToInt(stagecount));	
	}
	return Plugin_Handled;	
}

public UpdateTierCallback(Handle:owner, Handle:hndl, const String:error[], any:tier)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on UpdateTier: %s", error);
		return;
	}
	
	LoadMapTier();
}

public UpdateStageCountCallback(Handle:owner, Handle:hndl, const String:error[], any:tier)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on UpdateStageCount: %s", error);
		return;
	}
	
	LoadMapTier();
}

public Native_GetMapTier(Handle:plugin, numParams)
{
	return g_maptier;
}

public Native_SetMapTier(Handle:plugin, numParams)
{
	new tier = GetNativeCell(1);
	decl String:query[256];
	Format(query, sizeof(query), "UPDATE maptier SET tier = '%d' WHERE map = '%s'", tier, g_currentMap);
	SQL_TQuery(g_hSQL, UpdateTierCallback, query, g_maptier, DBPrio_Normal);	
}

public Native_GetStageCount(Handle:plugin, numParams)
{
	return g_maptier;
}

public Native_SetStageCount(Handle:plugin, numParams)
{
	new stagecount = GetNativeCell(1);
	decl String:query[256];
	Format(query, sizeof(query), "UPDATE maptier SET stagecount = '%d' WHERE map = '%s'", stagecount, g_currentMap);
	SQL_TQuery(g_hSQL, UpdateStageCountCallback, query, g_stagecount, DBPrio_Normal);	
}