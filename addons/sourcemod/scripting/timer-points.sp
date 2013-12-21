#pragma semicolon 1

#include <sourcemod>
#include <adminmenu>

#include <colors>
#include <smlib>
#include <timer>
#include <timer-logging>
#include <timer-teams>
#include <timer-config_loader.sp>

#define WIN_SCALE 0.04
#define LOOSE_SCALE 0.95

public Plugin:myinfo =
{
    name        = "[Timer] Point System",
    author      = "Zipcore",
    description = "Point component for [Timer]",
    version     = PL_VERSION,
    url         = "zipcore#googlemail.com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-points");
	
	CreateNative("Timer_AddPoints", Native_AddPoints);
	CreateNative("Timer_GetPoints", Native_GetPoints);
	CreateNative("Timer_RemovePoints", Native_RemovePoints);
	CreateNative("Timer_SetPoints", Native_SetPoints);
	CreateNative("Timer_SavePoints", Native_SavePoints);
	CreateNative("Timer_GetPointsChallengeWin", Native_GetPointsChallengeWin);
	CreateNative("Timer_GetPointsChallengeLoose", Native_GetPointsChallengeLoose);
	
	return APLRes_Success;
}

new g_iPoints[MAXPLAYERS+1] = { -1, ... };
new g_iPointsOld[MAXPLAYERS+1] = { -1, ... };
new bool:g_bWaitSQL[MAXPLAYERS+1] = { false, ... };

enum EQueries
{
	E_QCreate = 0,
	E_QInsert,
	E_QSelect,
	E_QDelete,
	E_QUpdate,
	E_QUpdateName,
	E_QMax
};

new stock const String:SQLQueries[E_QMax][] =
{
	"CREATE TABLE IF NOT EXISTS points ( id INTEGER PRIMARY KEY NOT NULL AUTO_INCREMENT, `name` varchar(64) CHARACTER SET utf8 NOT NULL, auth VARCHAR(32) UNIQUE, `points` int(11) NOT NULL);",
	"INSERT INTO points (name, auth, points) VALUES ('%s', '%s', '%d');",
	"SELECT points FROM points WHERE auth = '%s' LIMIT 0 , 1;",
	"DELETE FROM points WHERE auth = '%s';",
	"UPDATE points SET points = '%d' WHERE auth = '%s';",
	"UPDATE points SET name = '%s' WHERE auth = '%s';"
};

new Handle:g_hSQL;

new g_reconnectCounter = 0;

public OnPluginStart()
{
	LoadPhysics();
	LoadTimerSettings();
	
	LoadTranslations("common.phrases");
	LoadTranslations("timer.phrases");	

	ConnectSQL();
}

public OnMapStart()
{
	LoadPhysics();
	LoadTimerSettings();
}

public OnChallengeConfirm(client, creator)
{
	
}

public OnChallengeStart(client, creator)
{
	
}

public OnChallengeWin(winner, looser)
{
	
}

public OnChallengeForceEnd(winner, looser)
{
	
}

ConnectSQL()
{
	if(g_Settings[PointsEnable])
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
	db_createTables(driver);
	
	g_reconnectCounter = 1;
}

public db_createTables(String:driver[16])
{
	SQL_LockDatabase(g_hSQL);
	SQL_TQuery(g_hSQL, CreateSQLTableCallback, SQLQueries[E_QCreate]);
	SQL_FastQuery(g_hSQL, "SET NAMES  'utf8'");
	SQL_UnlockDatabase(g_hSQL);
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
}

public OnClientAuthorized(client, const String:auth[])
{
	g_iPoints[client] = -1;

	if(g_Settings[PointsEnable])
	{
		if (IsFakeClient(client))
		{
			return;
		}
		
		if (g_hSQL != INVALID_HANDLE)
		{
			g_bWaitSQL[client] = true;
			
			new String:name[MAX_NAME_LENGTH];
			
			GetClientName(client, name, sizeof(name));
			
			decl String:safeName[2 * strlen(name) + 1];
			SQL_EscapeString(g_hSQL, name, safeName, 2 * strlen(name) + 1);
			
			decl String:query2[255];
			Format(query2, sizeof(query2), SQLQueries[E_QUpdateName], safeName, auth);
			SQL_TQuery(g_hSQL, T_NoAction, query2, GetClientUserId(client));
			
			decl String:query[255];
			Format(query, sizeof(query), SQLQueries[E_QSelect], auth);
			SQL_TQuery(g_hSQL, T_ClientConnected, query, GetClientUserId(client));
		}
	}
}

public T_ClientConnected(Handle:owner, Handle:hndl, const String:error[], any:uid_client)
{
	new client = GetClientOfUserId(uid_client);
	g_bWaitSQL[client] = false;
	
	if (!client || !IsClientConnected(client))
	{
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		SetFailState(error);
	}
	else if (SQL_FetchRow(hndl))
	{
		g_iPoints[client] = SQL_FetchInt(hndl, 0);
		g_iPointsOld[client] = SQL_FetchInt(hndl, 0);
	}
}

public OnClientDisconnect(client)
{
	g_iPoints[client] = -1;
}

public T_NoAction(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState(error);
	}
}

public OnTimerStarted(client)
{
	if(g_Settings[PointsEnable])
	{
		if (g_iPoints[client] == -1 && g_hSQL != INVALID_HANDLE && !IsFakeClient(client) && !g_bWaitSQL[client])
		{
			if(!g_bWaitSQL[client]) 
			{
				g_iPoints[client] = 0;
				Client_Insert(client);
			}
			else
			{
				CreateTimer(1.0, Timer_CheckDB, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}

stock Client_Insert(client)
{
	new String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));
	
	new String:name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	decl String:safeName[2 * strlen(name) + 1];
	SQL_EscapeString(g_hSQL, name, safeName, 2 * strlen(name) + 1);
	
	decl String:query[255];
	Format(query, sizeof(query), SQLQueries[E_QInsert], safeName, auth, g_iPoints[client]);
	SQL_TQuery(g_hSQL, T_NoAction, query, GetClientUserId(client));
}

public Action:Timer_CheckDB(Handle:timer, any:client)
{
	if(Client_IsValid(client, true))
	{
		Client_Insert(client);
	}
	else
	{
		CreateTimer(1.0, Timer_CheckDB, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Stop;
}

public Native_AddPoints(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new newpoints = GetNativeCell(1);
	
	g_iPoints[client] += newpoints;
}

public Native_SavePoints(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	if (g_hSQL != INVALID_HANDLE && g_iPoints[client] > 0 && !IsFakeClient(client))
	{
		new String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));
		
		decl String:query[255];
		Format(query, sizeof(query), SQLQueries[E_QUpdate], g_iPoints[client], auth);
		SQL_TQuery(g_hSQL, T_NoAction, query, GetClientUserId(client));
		return true;
	}
	else return false;
}

public Native_GetPoints(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return g_iPoints[client];
}

public Native_RemovePoints(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new points = GetNativeCell(2);
	
	g_iPoints[client] -= points;
	
	if(g_iPoints[client] < 0) g_iPoints[client] = 0;
	return g_iPoints[client];
}

public Native_SetPoints(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new points = GetNativeCell(2);
	
	g_iPoints[client] = points;
	
	if(g_iPoints[client] < 0) g_iPoints[client] = 0;
	return g_iPoints[client];
}

public Native_GetPointsChallengeWin(Handle:plugin, numParams)
{
	new looser = GetNativeCell(1);
	
	return GetChallengeWin(looser);
}

public Native_GetPointsChallengeLoose(Handle:plugin, numParams)
{
	new looser = GetNativeCell(1);
	
	return GetChallengeLoose(looser);
}

stock GetChallengeWin(looser)
{
	new win = RoundToFloor(g_iPoints[looser]*WIN_SCALE);
	if(win > 100) win = 100;
	return win;
}

stock GetChallengeLoose(looser)
{
	new loose = RoundToFloor(GetChallengeWin(looser)*LOOSE_SCALE);
	if(loose > 100) loose = 100;
	return loose;
}

public OnTimerRecord(client, bonus, mode, Float:time, Float:lasttime, currentrank, newrank)
{
	if(g_Settings[PointsEnable])
	{
		new tier = Timer_GetTier();
		
		//give less points for short end & bonus 
		if(bonus != 0) tier = 1;
		
		new bool:ranked = bool:Timer_IsModeRanked(mode);
		new total = Timer_GetTotalRank(false, bonus);
		new finishcount = Timer_GetFinishCount(mode, bonus, currentrank);
		if(ranked)
		{
			new points = GetRecordPoints(lasttime > time, bonus, mode, tier, finishcount, total, currentrank, newrank);
			
			g_iPoints[client] += points;
			if(points > 0) CPrintToChat(client, "%s {olive}You got {lightred}%d points {olive}. Now you have {lightred}%d points{olive}.", PLUGIN_PREFIX2, points, g_iPoints[client]);
		}
	}
}

stock GetRecordPoints(bool:timeimproved, bonus, mode, tier, finishcount, total, currentrank, newrank)
{
	new Float:points = 0.0;
	new totalbonus = GetTotalBonus(total);
	new Float:style_scale = g_Physics[mode][ModePointsMulti];
	new Float:tier_scale = 0.0;
	
	if(tier == 1)
		tier_scale = g_Settings[Tier1Scale];
	else if(tier == 2)
		tier_scale = g_Settings[Tier2Scale];
	else if(tier == 3)
		tier_scale = g_Settings[Tier3Scale];
	else if(tier == 4)
		tier_scale = g_Settings[Tier4Scale];
	else if(tier == 5)
		tier_scale = g_Settings[Tier5Scale];

	/* Anyway */
	points += g_Settings[PointsAnyway]*tier_scale*style_scale; // 1-5 for first 5 records on this map
	//PrintToChatAll("a %.1f", points);
	
	/* First Record */
	if(finishcount == 0)
	{
		points += g_Settings[PointsFirst]*tier_scale*style_scale; // 20-100 for first personal record on this map
		//PrintToChatAll("f %.1f", points);
	}
	
	/* First 5 */
	if(finishcount < 5)
	{
		points += g_Settings[PointsFirst5]*tier_scale*style_scale; // 1-5 for first 5 records on this map
		//PrintToChatAll("f5 %.1f", points);
	}
	
	/* First 10 */
	if(finishcount < 10)
	{
		points += g_Settings[PointsFirst10]*tier_scale*style_scale; // 1-5 for first 10 records on this map
		//PrintToChatAll("f10 %.1f", points);
	}
	
	/* First 25 */
	if(finishcount < 25)
	{
		points += g_Settings[PointsFirst25]*tier_scale*style_scale; // 1-5 for first 25 records on this map
		//PrintToChatAll("f25 %.1f", points);
	}
	
	/* First 50 */
	if(finishcount < 50)
	{
		points += g_Settings[PointsFirst50]*tier_scale*style_scale; // 1-5 for first 50 records on this map
		//PrintToChatAll("f50 %.1f", points);
	}
	
	/* First 100 */
	if(finishcount < 100)
	{
		points += g_Settings[PointsFirst100]*tier_scale*style_scale; // 1-5 for first 100 records on this map
		//PrintToChatAll("f100 %.1f", points);
	}
	
	/* First 250 */
	if(finishcount < 250)
	{
		points += g_Settings[PointsFirst250]*tier_scale*style_scale; // 1-5 for first 250 records on this map
		//PrintToChatAll("f250 %.1f", points);
	}
	
	/* Iproved Time */
	if(timeimproved)
	{
		points += g_Settings[PointsImprovedTime]*tier_scale*style_scale; // 1-5 improved yourself (time)
		//PrintToChatAll("it %f.1f", points);
	}
	
	/* Iproved Rank */
	if(currentrank > newrank)
	{
		points += g_Settings[PointsImprovedRank]*tier_scale*style_scale; // 3-15 improved yourself (rank)
		//PrintToChatAll("ir %f.1f", points);
	}
	
	/* Break World-Record Self */
	if(newrank == 1 && total > 10 && currentrank == newrank)
	{
		points += g_Settings[PointsNewWorldRecordSelf]*tier_scale*style_scale; // 2-10 for breaking own world record
		points += totalbonus;
		//PrintToChatAll("wrs %.1f", points);
	}
	else if(currentrank > newrank)
	{
		/* Break World-Record */
		if(newrank == 1 && total > 10 && finishcount == 0)
		{
			points += g_Settings[PointsNewWorldRecord]*tier_scale*style_scale; // 10-50 for new world record
			points += totalbonus;
			//PrintToChatAll("wr %.1f", points);
		} 
		
		/* Top 10 */
		if(newrank <= 10 && total > 25 && (currentrank > 10 || finishcount == 0))
		{
			points += g_Settings[PointsTop10Record]*tier_scale*style_scale; // 6-30 new top10 record
			points += totalbonus;
			///PrintToChatAll("t10 %.1f", points);
		}
		
		/* Top 25 */
		if(newrank <= 25 && total > 50 && (currentrank > 25 || finishcount == 0))
		{
			points += g_Settings[PointsTop25Record]*tier_scale*style_scale; // 5-25 new top25 record
			points += totalbonus;
		}
		
		/* Top 50 */
		if(newrank <= 50 && total > 100 && (currentrank > 50 || finishcount == 0))
		{
			points += g_Settings[PointsTop50Record]*tier_scale*style_scale; // 4-20 new top50 record
			points += totalbonus;
		}
		
		/* Top 100 */
		if(newrank <= 100 && total > 200 && (currentrank > 100 || finishcount == 0))
		{
			points += g_Settings[PointsTop100Record]*tier_scale*style_scale; // 3-15 new top100 record
			points += totalbonus;
		}
		
		/* Top 250 */
		if(newrank <= 250 && total > 500 && (currentrank > 250 || finishcount == 0))
		{
			points += g_Settings[PointsTop250Record]*tier_scale*style_scale; // 2-10 new top250 record
			points += totalbonus;
		}
		
		/* Top 500 */
		if(newrank <= 500 && total > 750 && (currentrank > 500 || finishcount == 0))
		{
			points += g_Settings[PointsTop500Record]*tier_scale*style_scale; // 1-5 new top500 record
			points += totalbonus;
		}
	}
	
	return RoundToFloor(points);
}

stock GetTotalBonus(total)
{
	if(total != 0)
	{
		if(total >= 1 && total <= 3)
		{
			return 3;
		}
		else if(total >= 4 && total <= 10)
		{
			return 5;
		}
		else if(total >= 11 && total <= 25)
		{
			return 10;
		}
		else if(total >= 26 && total <= 50)
		{
			return 20;
		}
		else if(total >= 51 && total <= 100)
		{
			return 30;
		}
		else if(total >= 101 && total <= 200)
		{
			return 40;
		}
		else if(total >= 201)
		{
			return 50;
		}
	}
	
	return 1;
}