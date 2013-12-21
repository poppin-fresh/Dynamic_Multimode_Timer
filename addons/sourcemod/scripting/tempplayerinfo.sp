public Plugin:myinfo = {
	name = "SurfTimer TempPlayerinfo",
	author = "das d!",
	description = "private",
	version = "1.0",
	url = "www.devil-hunter-multigaming.de"
}

enum eMain
{
    Handle:eMain_Pack,
    Handle:eMain_Menu
}

enum eMain2
{
    Handle:eMain2_Pack,
    Handle:eMain2_Menu
}

enum eMain3
{
    Handle:eMain3_Pack,
    Handle:eMain3_Menu
}

new Handle:g_hDb = INVALID_HANDLE;
new String:g_MapName[32];
new g_RowCount[MAXPLAYERS+1];
new g_PointRowCount[MAXPLAYERS+1];
new g_MainMenu[MAXPLAYERS+1][eMain];
new g_MainMapMenu[MAXPLAYERS+1][eMain2];
//new g_MainMapMenu1[MAXPLAYERS+1][eMain3];
new g_MapCount;
new g_BonusMapCount;
new g_MenuPos[MAXPLAYERS+1];

public OnPluginStart(){
	RegConsoleCmd("sm_playerinfo", Client_PlayerInfo, "playerinfo");
	db_setupDatabase();
	countmaps();
	countbonusmaps();
}

public OnMapStart()
{
	GetCurrentMap(g_MapName, 32);
	countmaps();
	countbonusmaps();
}

public db_setupDatabase()
{
	decl String:Error[255];
	g_hDb = SQL_Connect("timer", false, Error, 255);
	
	//if a connection canot be made
	if(g_hDb == INVALID_HANDLE)
	{
		LogError("Unable to connect to database (%s)", Error);
		return;
	}
}

// SQL Querys ###########################################################################################################################################################################################################################################

new String:sql_QueryPlayerName[] = "SELECT name, auth FROM round WHERE name LIKE \"%%%s%%\" ORDER BY `round`.`name` ASC, `round`.`auth` ASC;";
new String:sql_selectSingleRecord[] = "SELECT auth, name, jumps, time, date, rank, finishcount, avgspeed, maxspeed, finishspeed FROM round WHERE auth LIKE '%s' AND map = '%s' AND bonus = '0';";
new String:sql_selectPlayerRowCount[] = "SELECT name FROM round WHERE time <= (SELECT time FROM round WHERE auth = '%s' AND map = '%s' AND bonus = '%i') AND map = '%s' AND bonus = '%i' ORDER BY time;";

new String:sql_selectPlayer_Points[] = "SELECT auth, lastname, points FROM ranks WHERE auth LIKE '%s' AND points NOT LIKE '0';";
new String:sql_selectPlayerPRowCount[] = "SELECT lastname FROM ranks WHERE points >= (SELECT points FROM ranks WHERE auth = '%s' AND points NOT LIKE '0') AND points NOT LIKE '0' ORDER BY points;";

new String:sql_selectPlayerMaps[] = "SELECT time, map, auth FROM round WHERE auth LIKE '%s' AND bonus = '0' ORDER BY map ASC;";
new String:sql_selectPlayerMapsBonus[] = "SELECT time, map, auth FROM round WHERE auth LIKE '%s' AND bonus = '1' ORDER BY map ASC;";
new String:sql_countmaps[] = "SELECT map FROM mapzone WHERE level_id = '1' GROUP BY map ORDER BY map ASC;";
new String:sql_countbonusmaps[] = "SELECT map FROM mapzone WHERE level_id = '1001' GROUP BY map ORDER BY map ASC;";

new String:sql_selectPlayerMapRecord[] = "SELECT auth, name, jumps, time, date, rank, finishcount, avgspeed, maxspeed, finishspeed FROM round WHERE auth LIKE '%s' AND map = '%s' AND bonus = '%i';";

// SQL Querys Ende #######################################################################################################################################################################################################################################


// Zähle Maps nach Startzone Typ ########################################################################################################################################################################################################################

public countmaps()
{
	decl String:Query[255];
	Format(Query, 255, sql_countmaps);
	SQL_TQuery(g_hDb, SQL_CountMapCallback, Query, false);
}

public countbonusmaps()
{
	decl String:Query[255];
	Format(Query, 255, sql_countbonusmaps);
	SQL_TQuery(g_hDb, SQL_CountMapCallback, Query, true);
}

public SQL_CountMapCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	new bool:BonusMap = data;
	if(hndl == INVALID_HANDLE)
		LogError("Error getting mapcount (%s)", error);
	
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl) && !BonusMap)
	{
		g_MapCount = SQL_GetRowCount(hndl);
	}
	else if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl) && BonusMap)
	{
		g_BonusMapCount = SQL_GetRowCount(hndl);
	}
}

// Zähle Maps nach Startzone Typ Ende ########################################################################################################################################################################################################################


// Setup !playerinfo cmd #####################################################################################################################################################################################################################################

public Action:Client_PlayerInfo(client, args)
{
	if(args < 1)
	{
		decl String:SteamID[32];
		decl String:PlayerName[MAX_NAME_LENGTH+1];
		decl String:buffer[512];
		GetClientAuthString(client, SteamID, 32);
		GetClientName(client, PlayerName, sizeof(PlayerName));
		new Handle:pack = CreateDataPack();
		WritePackCell(pack, client);
		WritePackString(pack, SteamID);
		WritePackString(pack, PlayerName);
		Format(buffer, sizeof(buffer), "%d", pack);
		
		Menu_PlayerInfo(client, buffer);
	}
	else if(args >= 1)
	{
		decl String:NameBuffer[256], String:NameClean[256];
		GetCmdArgString(NameBuffer, sizeof(NameBuffer));
		new startidx = 0;
		new len = strlen(NameBuffer);
		
		if ((NameBuffer[0] == '"') && (NameBuffer[len-1] == '"'))
		{
			startidx = 1;
			NameBuffer[len-1] = '\0';
		}
		
		Format(NameClean, sizeof(NameClean), "%s", NameBuffer[startidx]);

		QueryPlayerName(client, NameClean);
	}
	return Plugin_Handled;
}

// Setup !playerinfo cmd Ende #####################################################################################################################################################################################################################################


// Lade alle Player mit dem Angegeben Namen %% wildcards #####################################################################################################################################################################################################

public QueryPlayerName(client, String:QueryPlayerName[256])
{
	decl String:Query[255];
	//escape some quote characters that could mess up the Query
	decl String:szName[MAX_NAME_LENGTH*2+1];
	SQL_QuoteString(g_hDb, QueryPlayerName, szName, MAX_NAME_LENGTH*2+1);
	
	Format(Query, 255, sql_QueryPlayerName, szName);
	
	SQL_TQuery(g_hDb, SQL_QueryPlayerNameCallback, Query, client);
}

public SQL_QueryPlayerNameCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		LogError("Error loading playername (%s)", error);
		
	new client = data;
	decl String:PlayerName[256];
	decl String:SteamID[256];
	decl String:PlayerSteam[256];
	decl String:PlayerChkDup[256];
	decl String:buffer[512];
	PlayerChkDup = "zero";
	
	// Begin Menu
	new Handle:menu = CreateMenu(Menu_PlayerSearch);
	SetMenuTitle(menu, "Playersearch\n ");
	
	// get player names
	if(SQL_HasResultSet(hndl)){
		// Loop over
		new i = 0;
		while (SQL_FetchRow(hndl))
		{
			if (i <= 99)
			{
				SQL_FetchString(hndl, 0, PlayerName, 256);
				SQL_FetchString(hndl, 1, SteamID, 256);
				Format(PlayerSteam, 256, "%s - %s",PlayerName, SteamID);
				if(!StrEqual(PlayerChkDup, SteamID, false))
				{
					new Handle:pack = CreateDataPack();
					WritePackCell(pack, client);
					WritePackString(pack, SteamID);
					WritePackString(pack, PlayerName);
					Format(buffer, sizeof(buffer), "%d", pack);
					AddMenuItem(menu, buffer, PlayerSteam);
					
					Format(PlayerChkDup, 256, "%s",SteamID);
					i++;
				}
				else
				{
					Format(PlayerChkDup, 256, "%s",SteamID);
				}
			}
		}
		if((i == 0))
		{
			AddMenuItem(menu, "nope", "No Player found...", ITEMDRAW_DISABLED);
		}
		if(i > 99)
		{
			AddMenuItem(menu, "many", "More than 100 Players found.", ITEMDRAW_DISABLED);
			AddMenuItem(menu, "speci", "Please be more specific.", ITEMDRAW_DISABLED);
		}
	}
	else{
		AddMenuItem(menu, "nope", "No Player found...", ITEMDRAW_DISABLED);
	}
	
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

// Lade alle Player mit dem Angegeben Namen %% wildcards Ende #####################################################################################################################################################################################################


// Main Menu ########################################################################################################################################################################################################################

public Menu_PlayerInfo(client, String:data[512])
{
	g_MainMenu[client][eMain_Pack] = Handle:StringToInt(data); 
	ResetPack(g_MainMenu[client][eMain_Pack]);
	ReadPackCell(g_MainMenu[client][eMain_Pack]);
	decl String:SteamID[256];
	ReadPackString(g_MainMenu[client][eMain_Pack], SteamID, 256);
	decl String:PlayerName[256];
	ReadPackString(g_MainMenu[client][eMain_Pack], PlayerName, 256);
	//CloseHandle(pack);

	g_MainMenu[client][eMain_Menu] = CreateMenu(Menu_PlayerInfo_Handler);
	SetMenuTitle(g_MainMenu[client][eMain_Menu], "%s's Overview\n(%s)\n ", PlayerName, SteamID);
	AddMenuItem(g_MainMenu[client][eMain_Menu], data, "View Record/Rank (current Map)");
	AddMenuItem(g_MainMenu[client][eMain_Menu], data, "View Points/Rank");
	AddMenuItem(g_MainMenu[client][eMain_Menu], data, "View all Records");
	AddMenuItem(g_MainMenu[client][eMain_Menu], data, "View all Records (Bonus)");
	SetMenuExitButton(g_MainMenu[client][eMain_Menu], true);
	DisplayMenu(g_MainMenu[client][eMain_Menu], client, MENU_TIME_FOREVER);
}

// Main Menu Ende ########################################################################################################################################################################################################################


// SQL Callbacks ########################################################################################################################################################################################################################

public SQL_ViewSingleRecordCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		LogError("Error loading single record (%s)", error);
	
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	decl String:MapName[32];
	ReadPackString(pack, MapName, 32);
	
	CloseHandle(pack);
	
	new Handle:menu = CreateMenu(Menu_Stock_Handler);
	SetMenuTitle(menu, "Record Info\n ");
	
	//if there is a player record
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl)){
	
		decl String:SteamId[32];
		decl String:PlayerName[MAX_NAME_LENGTH];
		decl String:Date[20];
		new rank;
		new finishcount;
		
		//get the result
		SQL_FetchString(hndl, 0, SteamId, 32);
		SQL_FetchString(hndl, 1, PlayerName, MAX_NAME_LENGTH);
		SQL_FetchString(hndl, 4, Date, 20);
		rank = SQL_FetchInt(hndl, 5);
		finishcount = SQL_FetchInt(hndl, 6);
		new Float:avgspeed = SQL_FetchFloat(hndl, 7);
		new Float:maxspeed = SQL_FetchFloat(hndl, 8);
		new Float:finishspeed = SQL_FetchFloat(hndl, 9);
		
		decl String:LineDate[32];
		Format(LineDate, 32, "Date: %s", Date);
		decl String:LinePLSteam[128];
		Format(LinePLSteam, 128, "Player: %s (%s)", PlayerName, SteamId);
		decl String:LineRank[128];
		Format(LineRank, 128, "Rank: #%i on %s [FR: #%i | FC: %i]", g_RowCount[client], MapName, rank, finishcount);
		decl String:LineTime[128];
		decl String:Time[32];		
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 3), Time, 16, 2);
		Format(LineTime, 128, "Time: %s", Time);
		decl String:LineSpeed[128];
		Format(LineSpeed, 128, "Speed [Avg: %.2f | Max: %.2f | Fin: %.2f]", avgspeed, maxspeed, finishspeed);
		
		AddMenuItem(menu, "1", LineDate);
		AddMenuItem(menu, "2", LinePLSteam);
		AddMenuItem(menu, "3", LineRank);
		AddMenuItem(menu, "4", LineTime);
		AddMenuItem(menu, "5", LineSpeed);
		
		SetMenuExitButton(menu, true);
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}else{ //no valid record
		AddMenuItem(menu, "nope", "No Record Found...");
		SetMenuExitButton(menu, true);
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

public SQL_ViewPlayerMapRecordCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		LogError("Error loading single record (%s)", error);
	
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	decl String:MapName[32];
	ReadPackString(pack, MapName, 32);
	decl String:SteamID[256];
	ReadPackString(pack, SteamID, 256);
	new Bonus = ReadPackCell(pack);
	//g_MenuPos[client] = ReadPackCell(pack);
	
	//CloseHandle(pack);
	
	new Handle:menu = CreateMenu(Menu_Stock_Handler2);
	if(!Bonus)
	{
		SetMenuTitle(menu, "Record Info\n ");
	}
	else
	{
		SetMenuTitle(menu, "Bonus Record Info\n ");
	}
	
	//if there is a player record
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl)){
	
		decl String:SteamId[32];
		decl String:PlayerName[MAX_NAME_LENGTH];
		decl String:Date[20];
		new rank;
		new finishcount;
		
		//get the result
		SQL_FetchString(hndl, 0, SteamId, 32);
		SQL_FetchString(hndl, 1, PlayerName, MAX_NAME_LENGTH);
		SQL_FetchString(hndl, 4, Date, 20);
		rank = SQL_FetchInt(hndl, 5);
		finishcount = SQL_FetchInt(hndl, 6);
		new Float:avgspeed = SQL_FetchFloat(hndl, 7);
		new Float:maxspeed = SQL_FetchFloat(hndl, 8);
		new Float:finishspeed = SQL_FetchFloat(hndl, 9);
		
		decl String:LineDate[32];
		Format(LineDate, 32, "Date: %s", Date);
		decl String:LinePLSteam[128];
		Format(LinePLSteam, 128, "Player: %s (%s)", PlayerName, SteamId);
		decl String:LineRank[128];
		Format(LineRank, 128, "Rank: #%i on %s [FR: #%i | FC: %i]", g_RowCount[client], MapName, rank, finishcount);
		decl String:LineTime[128];
		decl String:Time[32];		
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 3), Time, 16, 2);
		Format(LineTime, 128, "Time: %s", Time);
		decl String:LineSpeed[128];
		Format(LineSpeed, 128, "Speed [Avg: %.2f | Max: %.2f | Fin: %.2f]", avgspeed, maxspeed, finishspeed);
		
		AddMenuItem(menu, "1", LineDate);
		AddMenuItem(menu, "2", LinePLSteam);
		AddMenuItem(menu, "3", LineRank);
		AddMenuItem(menu, "4", LineTime);
		AddMenuItem(menu, "5", LineSpeed);
		
		SetMenuExitButton(menu, true);
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}else{ //no valid record
		AddMenuItem(menu, "nope", "No Record Found...");
		SetMenuExitButton(menu, true);
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

public SQL_PRowCountCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
		LogError("Error viewing player point rowcount (%s)", error);
	
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		g_PointRowCount[client] = SQL_GetRowCount(hndl);
	}
}

public SQL_GetRowCountCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		LogError("Error getting rowcount (%s)", error);
		
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		g_RowCount[client] = SQL_GetRowCount(hndl);
	}
}

public SQL_PlayerPointsCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
		LogError("Error loading player points (%s)", error);
	
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	
	CloseHandle(pack);
	
	new Handle:menu = CreateMenu(Menu_Stock_Handler);
	SetMenuTitle(menu, "Points Info\n ");
	
	//if there is a player record
	if(SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		decl String:SteamId[32];
		decl String:Name[128];
		decl String:Points[64];
		new points;
		
		//get the result
		SQL_FetchString(hndl, 0, SteamId, 32);
		SQL_FetchString(hndl, 1, Name, 128);
		SQL_FetchString(hndl, 2, Points, 64);
		points = SQL_FetchInt(hndl, 2);
		
		//display a panel
		decl String:LineName[128];
		decl String:LinePoints[64];
		decl String:LinePointRank[64];
		Format(LineName, 128, "Player: %s (%s)", Name, SteamId);
		Format(LinePoints, 64, "Points: %i", points);
		Format(LinePointRank, 64, "Rank: #%i", g_PointRowCount[client]);
		
		AddMenuItem(menu, "1", LineName);
		AddMenuItem(menu, "2", LinePoints);
		AddMenuItem(menu, "3", LinePointRank);
		SetMenuExitButton(menu, true);
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}


public SQL_ViewPlayerMapsCallback(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		LogError("[Timer] Error loading playerinfo (%s)", error);
	
	new Handle:pack = data;
	ResetPack(pack);
	
	new client = ReadPackCell(pack);
	new bonus = ReadPackCell(pack);
	
	CloseHandle(pack);

	decl String:szValue[64];
	decl String:szMapName[32];
	decl String:szVrTime[16];
	decl String:SteamID[256];
	//decl String:PlayerStMapData[256];
	decl String:buffer[512];
	
	// Begin Menu
	g_MainMapMenu[client][eMain2_Menu] = CreateMenu(MapMenu_Stock_Handler);
	//new Handle:menu = CreateMenu(MapMenu_Stock_Handler);
	new mapscomplete = 0;
	if(SQL_HasResultSet(hndl)){
		mapscomplete = SQL_GetRowCount(hndl);
	}
	/// Calc Percent
	new Float: mapcom_fl = float(mapscomplete);
	new Float: mapcou_fl;
	if(!bonus)
	{
		mapcou_fl = float(g_MapCount);
	}
	else
	{
		mapcou_fl = float(g_BonusMapCount);
	}
	new Float: Com_Per_fl = (mapcom_fl/mapcou_fl)*100;
	
	if(!bonus)
	{
		SetMenuTitle(g_MainMapMenu[client][eMain2_Menu], "%i of %i (%.2f%%) Maps completed\nRecords:\n ", mapscomplete, g_MapCount, Com_Per_fl);
	}
	else
	{
		SetMenuTitle(g_MainMapMenu[client][eMain2_Menu], "%i of %i (%.2f%%) Bonuses completed\nRecords:\n ", mapscomplete, g_BonusMapCount, Com_Per_fl);
	}
	
	if(SQL_HasResultSet(hndl))
	{
		new i = 1;
		// Loop over
		while (SQL_FetchRow(hndl))
		{
			SQL_FetchString(hndl, 1, szMapName, 32);
			SQL_FetchString(hndl, 2, SteamID, 256);
			Timer_SecondsToTime(SQL_FetchFloat(hndl, 0), szVrTime, 16, 2);
			Format(szValue, 64, "%s - %s",szMapName, szVrTime);
			//Format(PlayerStMapData, 256, "%s:...||e|x|||p|l|:|.%s",szMapName, SteamID);
			
			new Handle:pack2 = CreateDataPack();
			WritePackCell(pack2, client);
			WritePackString(pack2, szMapName);
			WritePackString(pack2, SteamID);
			WritePackCell(pack2, bonus);
			Format(buffer, sizeof(buffer), "%d", pack2);
			
			AddMenuItem(g_MainMapMenu[client][eMain2_Menu], buffer, szValue);
			i++;
		}
		if(i == 1)
		{
			AddMenuItem(g_MainMapMenu[client][eMain2_Menu], "nope", "No Record found...");
		}
	}
	
	SetMenuExitBackButton(g_MainMapMenu[client][eMain2_Menu], true);
	DisplayMenu(g_MainMapMenu[client][eMain2_Menu], client, MENU_TIME_FOREVER);
	//////////////////////
}

// SQL Callbacks Ende ########################################################################################################################################################################################################################


// Menu Handlers ####################################################################################################################################################################################################################################

public Menu_PlayerSearch(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		new first_item = GetMenuSelectionPosition();
		DisplayMenuAtItem(menu, param1, first_item, MENU_TIME_FOREVER); 

		decl String:data[512];
		GetMenuItem(menu, param2, data, sizeof(data));

		Menu_PlayerInfo(param1, data);
	}
}

public Menu_PlayerInfo_Handler(Handle:menu, MenuAction:action,param1, param2)
{
	if ( action == MenuAction_Select )
	{
		new first_item = GetMenuSelectionPosition();
		DisplayMenuAtItem(menu, param1, first_item, MENU_TIME_FOREVER); 
		
		decl String:data[512];
		GetMenuItem(menu, param2, data, sizeof(data));
		g_MainMenu[param1][eMain_Pack] = Handle:StringToInt(data); 
		ResetPack(g_MainMenu[param1][eMain_Pack]);
		ReadPackCell(g_MainMenu[param1][eMain_Pack]);
		decl String:SteamID[256];
		ReadPackString(g_MainMenu[param1][eMain_Pack], SteamID, 256);
		decl String:PlayerName[256];
		ReadPackString(g_MainMenu[param1][eMain_Pack], PlayerName, 256);

		switch (param2)
		{
			case 0:
			{
				// View Record/Rank (current Map)
				decl String:Query[255];
				Format(Query, 255, sql_selectSingleRecord, SteamID, g_MapName);
				decl String:Query2[255];
				Format(Query2, 255, sql_selectPlayerRowCount, SteamID, g_MapName, 0, g_MapName, 0);
				
				new Handle:pack2 = CreateDataPack();
				WritePackCell(pack2, param1);
				WritePackString(pack2, g_MapName);
				
				SQL_TQuery(g_hDb, SQL_GetRowCountCallback, Query2, pack2);
				SQL_TQuery(g_hDb, SQL_ViewSingleRecordCallback, Query, pack2);
			}
			case 1:
			{
				//View Points/Rank
				decl String:szQuery[255];
				Format(szQuery, 255, sql_selectPlayer_Points, SteamID);
				decl String:Query2[255];
				Format(Query2, 255, sql_selectPlayerPRowCount, SteamID);

				new Handle:pack3 = CreateDataPack();
				WritePackCell(pack3, param1);

				SQL_TQuery(g_hDb, SQL_PRowCountCallback, Query2, pack3);
				SQL_TQuery(g_hDb, SQL_PlayerPointsCallback, szQuery, pack3);
			}
			case 2:
			{
				new bool: bonus = false;
				new Handle:pack4 = CreateDataPack();
				WritePackCell(pack4, param1);
				WritePackCell(pack4, bonus);
				
				
				decl String:szQuery[255];
				Format(szQuery, 255, sql_selectPlayerMaps, SteamID);
				SQL_TQuery(g_hDb, SQL_ViewPlayerMapsCallback, szQuery, pack4);
			}
			case 3:
			{
				new bool: bonus = true;
				new Handle:pack5 = CreateDataPack();
				WritePackCell(pack5, param1);
				WritePackCell(pack5, bonus);
				
				decl String:szQuery[255];
				Format(szQuery, 255, sql_selectPlayerMapsBonus, SteamID);
				SQL_TQuery(g_hDb, SQL_ViewPlayerMapsCallback, szQuery, pack5);
			}
		}
	}
}

public Menu_Stock_Handler(Handle:menu, MenuAction:action, param1, param2)
{
	if ( action == MenuAction_Select )
	{
		new first_item = GetMenuSelectionPosition();
		DisplayMenuAtItem(menu, param1, first_item, MENU_TIME_FOREVER); 
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		DisplayMenu(g_MainMenu[param1][eMain_Menu], param1, MENU_TIME_FOREVER);
	}
}

public Menu_Stock_Handler2(Handle:menu, MenuAction:action, param1, param2)
{
	if ( action == MenuAction_Select )
	{
		new first_item = GetMenuSelectionPosition();
		DisplayMenuAtItem(menu, param1, first_item, MENU_TIME_FOREVER); 
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		DisplayMenuAtItem(g_MainMapMenu[param1][eMain2_Menu], param1, g_MenuPos[param1], MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_End)
	{
		//CloseHandle(menu);
	}
}

public MapMenu_Stock_Handler(Handle:menu, MenuAction:action, param1, param2)
{
	if ( action == MenuAction_Select )
	{
		g_MenuPos[param1] = GetMenuSelectionPosition();
		DisplayMenuAtItem(menu, param1, g_MenuPos[param1], MENU_TIME_FOREVER); 
		
		decl String:data[512];
		GetMenuItem(menu, param2, data, sizeof(data));
		new Handle:pack = Handle:StringToInt(data); 
		ResetPack(pack);
		ReadPackCell(pack);
		decl String:MapName[256];
		ReadPackString(pack, MapName, 256);
		decl String:SteamID[256];
		ReadPackString(pack, SteamID, 256);
		new Bonus = ReadPackCell(pack);
		
		decl String:szQuery[255];
		Format(szQuery, 255, sql_selectPlayerMapRecord, SteamID, MapName, Bonus);
		decl String:Query2[255];
		Format(Query2, 255, sql_selectPlayerRowCount, SteamID, MapName, Bonus, MapName, Bonus);

		SQL_TQuery(g_hDb, SQL_GetRowCountCallback, Query2, pack);
		SQL_TQuery(g_hDb, SQL_ViewPlayerMapRecordCallback, szQuery, pack);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		DisplayMenu(g_MainMenu[param1][eMain_Menu], param1, MENU_TIME_FOREVER);
	}
}

// Menu Handlers Ende ####################################################################################################################################################################################################################################


public OnClientDisconnect(client){
	if(g_MainMenu[client][eMain_Pack] != INVALID_HANDLE){
		CloseHandle(g_MainMenu[client][eMain_Pack]);
		g_MainMenu[client][eMain_Pack] = INVALID_HANDLE;
	}
	
	if(g_MainMenu[client][eMain_Menu] != INVALID_HANDLE){
		CloseHandle(g_MainMenu[client][eMain_Menu]);
		g_MainMenu[client][eMain_Menu] = INVALID_HANDLE;
	}
	
	if(g_MainMapMenu[client][eMain2_Pack] != INVALID_HANDLE){
		CloseHandle(g_MainMapMenu[client][eMain2_Pack]);
		g_MainMapMenu[client][eMain2_Pack] = INVALID_HANDLE;
	}
	
	if(g_MainMapMenu[client][eMain2_Menu] != INVALID_HANDLE){
		CloseHandle(g_MainMapMenu[client][eMain2_Menu]);
		g_MainMapMenu[client][eMain2_Menu] = INVALID_HANDLE;
	}
}

stock Timer_SecondsToTime(Float:seconds, String:buffer[], maxlength, precision)
{
	new t = RoundToFloor(seconds);
	
	new hour, mins;
	
	if (t >= 3600)
	{
		hour = RoundToFloor(t / 3600.0);
		t = t % 3600;
    }
	
	if (t >= 60)
	{
		mins = RoundToFloor(t / 60.0);
		t = t % 60;
    }

	Format(buffer, maxlength, "");
	
	if (hour)
		Format(buffer, maxlength, "%s%02d:", buffer, hour);
	
	Format(buffer, maxlength, "%s%02d:", buffer, mins);
	
	if (precision == 1)
		Format(buffer, maxlength, "%s%04.1f", buffer, float(t) + seconds - RoundToFloor(seconds));
	else if (precision == 2)
		Format(buffer, maxlength, "%s%05.2f", buffer, float(t) + seconds - RoundToFloor(seconds));
	else if (precision == 3)
		Format(buffer, maxlength, "%s%06.3f", buffer, float(t) + seconds - RoundToFloor(seconds));
	else 
		Format(buffer, maxlength, "%s%02d", buffer, t);
}