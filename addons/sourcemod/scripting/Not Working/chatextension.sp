#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <basecomm>
#include <clientprefs>

#pragma semicolon 1
#define MAX_PLAYERS 256

//#define _DEBUG

//#define SQL_Support

#define VERSION "3.3"

/* word filter globals */
#define MAX_BADWORDS 1001
#define MAX_WORDLENGTH 255
new String: bad_words[MAX_BADWORDS][MAX_WORDLENGTH];
new String: blocked_words[MAX_BADWORDS][MAX_WORDLENGTH];
new String: blocked_commands[MAX_BADWORDS][MAX_WORDLENGTH];
new String: blocked_webwords[MAX_BADWORDS][MAX_WORDLENGTH];
new i_bc;
new i_bw;
new i_bweb;
new String:LogFile[PLATFORM_MAX_PATH + 1];
/* ------------------ */

/* chat color globals */
new Handle:g_hCookieHideChatColor;
new Handle:g_hCookieHideChat;
new Handle:g_hCookieHideOwnChatColor;
new Handle:configFile = INVALID_HANDLE;
new String:tag[MAXPLAYERS + 1][512];
new String:tagColor[MAXPLAYERS + 1][12];
new String:usernameColor[MAXPLAYERS + 1][12];
new String:chatColor[MAXPLAYERS + 1][12];


new bool:g_HideChatColors[MAXPLAYERS+1];
new bool:g_HideChat[MAXPLAYERS+1];
new bool:g_HideOwnChatColors[MAXPLAYERS+1];

new NotListed[MAXPLAYERS+1];
new Handle:AnnounceTimer[MAX_PLAYERS+1];
/* ------------------------ */

/* cvars */
new Handle:g_hcvarAnnounce = INVALID_HANDLE;
new bool:g_bAnnounce = false;

new Handle:g_hcvarDatabase = INVALID_HANDLE;
new String:g_sDatabase[128];
new bool:g_bDatabase = false;

new Handle:g_hcvarBadWordlog = INVALID_HANDLE;
new bool:g_bBadWordlog = false;

new Handle:g_hcvarDeadTalk = INVALID_HANDLE;
new bool:g_bDeadTalk = false;

new Handle:g_hcvarChatColors = INVALID_HANDLE;
new bool:g_bChatColors = false;

new Handle:g_hcvarWordFilter = INVALID_HANDLE;
new bool:g_bWordFilter = false;

new Handle:g_hcvarBlockBadChat = INVALID_HANDLE;
new bool:g_bBlockBadChat = false;
/* ------------------- */


#include "chatextension/chatmenu.sp"
#include "chatextension/load_chatblockcfg.sp"
#include "chatextension/load_chatcolorcfg.sp"
#include "chatextension/says.sp"
#include "chatextension/stocks.sp"
#include "chatextension/sql.sp"

public Plugin:myinfo = 
{
	name = "ChatExtension",
	author = "das d!",
	description = "Provide ChatColors/Wordfilter/SQL Support",
	version = VERSION,
};

public OnPluginStart()
{
	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_SayTeam);
	g_hCookieHideChatColor = RegClientCookie("cookie_hidechatcolor", "1 = on, 0 = off for colored chat", CookieAccess_Public);
	g_hCookieHideChat = RegClientCookie("cookie_hidechat", "1 = on, 0 = off for chat", CookieAccess_Public);
	g_hCookieHideOwnChatColor = RegClientCookie("cookie_hideownchatcolor", "1 = on, 0 = off for own chatcolors", CookieAccess_Public);
	RegConsoleCmd("sm_chatmenu", Client_ChatMenu, "ChatMenu");
	RegAdminCmd("sm_ce_rcc", Command_ReloadConfig, ADMFLAG_CONFIG, "Reloads Chat Colors config file");
	RegAdminCmd("sm_ce_rbw", Command_ReloadBadWords, ADMFLAG_CONFIG, "Reloads Bad Words config file");
	LoadConfig();
	ReadBadWords();
	
	decl String:CurrentDate[20];
	FormatTime(CurrentDate, sizeof(CurrentDate), "%d-%m-%y");
	BuildPath(Path_SM, LogFile, sizeof(LogFile), "logs/badwords_%s.log", CurrentDate);
	
	CreateConVar("sm_dhc_ChatExtension version", VERSION, "ChatExtension version", FCVAR_DONTRECORD|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	g_hcvarAnnounce    = CreateConVar("sm_ce_help_announce", "1", "Displays the help announce", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bAnnounce        = GetConVarBool(g_hcvarAnnounce);
	HookConVarChange(g_hcvarAnnounce, OnSettingChanged);
	
	g_hcvarDatabase    = CreateConVar("sm_ce_database", "", "Connect to a database (SurfTimer only)");
	GetConVarString(g_hcvarDatabase, g_sDatabase, sizeof(g_sDatabase));
	HookConVarChange(g_hcvarDatabase, OnSettingChanged);
	if(strlen(g_sDatabase) == 0){g_bDatabase = false;}else{g_bDatabase = true;}
	
	g_hcvarBadWordlog    = CreateConVar("sm_ce_log_badwords", "1", "Log Users who triggered a badword", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bBadWordlog        = GetConVarBool(g_hcvarBadWordlog);
	HookConVarChange(g_hcvarBadWordlog, OnSettingChanged);
	
	g_hcvarDeadTalk    = CreateConVar("sm_ce_deadtalk", "0", "Enable / Disable Deadtalk (0 = disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bDeadTalk        = GetConVarBool(g_hcvarDeadTalk);
	HookConVarChange(g_hcvarDeadTalk, OnSettingChanged);
	
	g_hcvarChatColors    = CreateConVar("sm_ce_chatcolors", "1", "Enable / Disable ChatColors (1 = enabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bChatColors        = GetConVarBool(g_hcvarChatColors);
	HookConVarChange(g_hcvarChatColors, OnSettingChanged);
	
	g_hcvarWordFilter    = CreateConVar("sm_ce_wordfilter", "1", "Enable / Disable Wordfilter (1 = enabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bWordFilter        = GetConVarBool(g_hcvarWordFilter);
	HookConVarChange(g_hcvarWordFilter, OnSettingChanged);
	
	g_hcvarBlockBadChat    = CreateConVar("sm_ce_blockbadchat", "1", "Enable / Disable Chat Output @ Badword trigger (1 = disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_bBlockBadChat        = GetConVarBool(g_hcvarBlockBadChat);
	HookConVarChange(g_hcvarBlockBadChat, OnSettingChanged);
	
	AutoExecConfig(true, "sm_chatextension_config");
	db_connectDatabase();						//see OnSettingsChanged
}

public OnMapStart()
{
	LoadConfig();
	ReadBadWords();
}

public Action:Command_ReloadBadWords(client, args)
{
	ReadBadWordsCl(client);
	ReplyToCommand(client, "[ChatExtension] Reloaded Bad Words config file.");
	return Plugin_Handled;
}

public Action:Command_ReloadConfig(client, args) {
	LoadConfig();
	ReplyToCommand(client, "[ChatExtension] Reloaded Color config file.");
	return Plugin_Handled;
}

public OnClientConnected(client) {
	Format(tag[client], sizeof(tag[]), "");
	Format(tagColor[client], sizeof(tagColor[]), "");
	Format(usernameColor[client], sizeof(usernameColor[]), "");
	Format(chatColor[client], sizeof(chatColor[]), "");
	NotListed[client] = 0;
}

public OnClientPostAdminCheck(client) {
#if defined _DEBUG
	PrintToChatAll("[ChatExtension] Checking client %N", client);
#endif
	// check the Steam ID first
	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));
	KvRewind(configFile);
	if(!KvJumpToKey(configFile, auth)) {
		KvRewind(configFile);
		KvGotoFirstSubKey(configFile);
		new AdminId:admin = GetUserAdmin(client);
		new AdminFlag:flag;
		decl String:configFlag[2];
		decl String:section[32];
		new bool:found = false;
		do {
			KvGetSectionName(configFile, section, sizeof(section));
			KvGetString(configFile, "flag", configFlag, sizeof(configFlag));
			if(StrEqual(configFlag, "") && StrContains(section, "STEAM_", false) == -1) {
				found = true;
				break;
			}
			if(!FindFlagByChar(configFlag[0], flag)) {
				continue;
			}
			if(GetAdminFlag(admin, flag)) {
				found = true;
				break;
			}
		} while(KvGotoNextKey(configFile));
		if(!found) {
#if defined _DEBUG
			PrintToChatAll("[ChatExtension] Didn't find client");
#endif
			NotListed[client] = 1;
			db_loadplayer(client);
			return;
		}
#if defined _DEBUG
		PrintToChatAll("[ChatExtension] Found client by flag");
#endif
	}
#if defined _DEBUG
	PrintToChatAll("[ChatExtension] Found client");
#endif
	OnClientConnected(client); // clear the old values!
	decl String:clientTagColor[12];
	decl String:clientNameColor[12];
	decl String:clientChatColor[12];
	KvGetString(configFile, "tag", tag[client], sizeof(tag[]));
	KvGetString(configFile, "tagcolor", clientTagColor, sizeof(clientTagColor));
	KvGetString(configFile, "namecolor", clientNameColor, sizeof(clientNameColor));
	KvGetString(configFile, "textcolor", clientChatColor, sizeof(clientChatColor));
	ReplaceString(tag[client], sizeof(tag[]), "#", "\x07");
	ReplaceString(tag[client], sizeof(tag[]), "*", "\x08");
	ReplaceString(clientTagColor, sizeof(clientTagColor), "#", "");
	ReplaceString(clientNameColor, sizeof(clientNameColor), "#", "");
	ReplaceString(clientChatColor, sizeof(clientChatColor), "#", "");
	new tagLen = strlen(clientTagColor);
	new nameLen = strlen(clientNameColor);
	new chatLen = strlen(clientChatColor);
	if(tagLen == 6 || tagLen == 8 || StrEqual(clientTagColor, "T", false) || StrEqual(clientTagColor, "G", false) || StrEqual(clientTagColor, "O", false)) {
		strcopy(tagColor[client], sizeof(tagColor[]), clientTagColor);
	}
	if(nameLen == 6 || nameLen == 8 || StrEqual(clientNameColor, "G", false) || StrEqual(clientNameColor, "O", false)) {
		strcopy(usernameColor[client], sizeof(usernameColor[]), clientNameColor);
	}
	if(chatLen == 6 || chatLen == 8 || StrEqual(clientChatColor, "T", false) || StrEqual(clientChatColor, "G", false) || StrEqual(clientChatColor, "O", false)) {
		strcopy(chatColor[client], sizeof(chatColor[]), clientChatColor);
	}
}

public OnClientPutInServer(client)
{
	// hole cookie und sperre chatcolors wenn cookie status = 1
	
	decl String:ChatColor_HideStatus[3];
	GetClientCookie(client, g_hCookieHideChatColor, ChatColor_HideStatus, sizeof(ChatColor_HideStatus));
	if(!strcmp(ChatColor_HideStatus, "1"))
	{
		g_HideChatColors[client] = true;
	}
	else
	{
		g_HideChatColors[client] = false;
	}
	
	// hole cookie und sperre chat wenn cookie status = 1
	
	decl String:Chat_HideStatus[3];
	GetClientCookie(client, g_hCookieHideChat, Chat_HideStatus, sizeof(Chat_HideStatus));
	if(!strcmp(Chat_HideStatus, "1"))
	{
		g_HideChat[client] = true;
	}
	else
	{
		g_HideChat[client] = false;
	}
	
	decl String:OwnChatColor_HideStatus[3];
	GetClientCookie(client, g_hCookieHideOwnChatColor, OwnChatColor_HideStatus, sizeof(OwnChatColor_HideStatus));
	if(!strcmp(OwnChatColor_HideStatus, "1"))
	{
		g_HideOwnChatColors[client] = true;
	}
	else
	{
		g_HideOwnChatColors[client] = false;
	}
	
	if(g_bAnnounce)
	{
		AnnounceTimer[client] = CreateTimer(30.0, announce, client);
	}
}

public Action:announce(Handle:timer, any:client){
	if(g_HideChat[client])
	{
		PrintToChat(client, "\x07000000[\x07ff0000C\x07ff8400h\x07ffea00a\x07a8ff00t\x073ae306C\x0700f6ffo\x070072ffl\x07002affo\x078400ffr\x07d200ffs\x07000000]\x07FFFFFF Note! Your Chat is disabled.");
	}
	if(g_HideChatColors[client])
	{
		PrintToChat(client, "\x07000000[\x07ff0000C\x07ff8400h\x07ffea00a\x07a8ff00t\x073ae306C\x0700f6ffo\x070072ffl\x07002affo\x078400ffr\x07d200ffs\x07000000]\x07FFFFFF Note! Your Chatcolors are disabled.");
	}
	if(g_HideOwnChatColors[client])
	{
		PrintToChat(client, "\x07000000[\x07ff0000C\x07ff8400h\x07ffea00a\x07a8ff00t\x073ae306C\x0700f6ffo\x070072ffl\x07002affo\x078400ffr\x07d200ffs\x07000000]\x07FFFFFF Note! Your own Chatcolors are disabled.");
	}
	PrintToChat(client, "\x07000000[\x07ff0000C\x07ff8400h\x07ffea00a\x07a8ff00t\x073ae306C\x0700f6ffo\x070072ffl\x07002affo\x078400ffr\x07d200ffs\x07000000]\x07FFFFFF type !chatmenu to change settings.");
	AnnounceTimer[client] = INVALID_HANDLE;
}

public OnClientDisconnect(client){
	if(AnnounceTimer[client] != INVALID_HANDLE){
		CloseHandle(AnnounceTimer[client]);
		AnnounceTimer[client] = INVALID_HANDLE;
	}
}

public Action:Client_ChatMenu(client, args)
{
	Show_ChatMenu(client);
	return Plugin_Handled;
}

public OnSettingChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(convar == g_hcvarAnnounce)
	{
		if(newValue[0] == '1')
			g_bAnnounce = true;
		else
			g_bAnnounce = false;
	}
	else if(convar == g_hcvarDatabase)
	{
		GetConVarString(g_hcvarDatabase, g_sDatabase, sizeof(g_sDatabase));
		if(strlen(g_sDatabase) == 0)
			g_bDatabase = false;
		else
		{
			g_bDatabase = true;
			db_connectDatabase();
		}
	}
	else if(convar == g_hcvarBadWordlog)
	{
		if(newValue[0] == '1')
			g_bBadWordlog = true;
		else
			g_bBadWordlog = false;
	}
	else if(convar == g_hcvarDeadTalk)
	{
		if(newValue[0] == '1')
			g_bDeadTalk = true;
		else
			g_bDeadTalk = false;
	}
	else if(convar == g_hcvarChatColors)
	{
		if(newValue[0] == '1')
			g_bChatColors = true;
		else
			g_bChatColors = false;
	}
	else if(convar == g_hcvarWordFilter)
	{
		if(newValue[0] == '1')
			g_bWordFilter = true;
		else
			g_bWordFilter = false;
	}
	else if(convar == g_hcvarBlockBadChat)
	{
		if(newValue[0] == '1')
			g_bBlockBadChat = true;
		else
			g_bBlockBadChat = false;
	}
}