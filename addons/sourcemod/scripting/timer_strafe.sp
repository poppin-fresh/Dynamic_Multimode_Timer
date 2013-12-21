#include <sourcemod>
#include <sdktools>
#include <smlib/arrays>
#include <timer>

#define MAX_STRAFES 5000

enum PlayerState
{
	bool:bHidePanel,
	bool:bShowBeam,
	bool:bBlockMode,
	Float:fBlockDistance,
	bool:bFailedBlock,
	bool:bDuck,
	bool:bHasDucked,
	Float:vJumpOrigin[3],
	Float:fPrestrafe,
	Float:fJumpDistance,
	Float:fHeightDelta,
	Float:fJumpHeight,
	Float:fEdge,
	nStrafeDir,
	nStrafes,
	cStrafeKey[MAX_STRAFES],
	Float:fStrafeGain[MAX_STRAFES],
	Float:fStrafeLoss[MAX_STRAFES],
	Float:fStrafeSync[MAX_STRAFES],
	nStrafeTicks[MAX_STRAFES],
	nStrafeTicksSynced[MAX_STRAFES],
	nTotalTicks,
	Float:fStamina,
	Float:fMaxSpeed,
	bool:bOn,
	String:sHUDHint[128],
	Handle:hBeamTimer,
	Float:vLastBeamOrigin[3],
}

new g_PlayerStates[MAXPLAYERS + 1][PlayerState];

public Plugin:myinfo = 
{
	name = "ljstats",
	author = "Miu",
	description = "longjump stats",
	version = "1.0",
	url = ""
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-strafes");
	CreateNative("Timer_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Timer_GetStrafeGain", Native_GetStrafeGain);
	CreateNative("Timer_GetStrafeLoss", Native_GetStrafeLoss);
	CreateNative("Timer_GetStrafePerc", Native_GetStrafePerc);
	
	return APLRes_Success;
}

public Native_GetStrafeCount(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return g_PlayerStates[client][nStrafes];
}

public Native_GetStrafeGain(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	new Gain, Loss;
	
	for(new i = 0; i < g_PlayerStates[client][nStrafes] && i < MAX_STRAFES; i++)
	{
		if(g_PlayerStates[client][fStrafeGain][i] > 50.0)
		{
			Gain++;
		}
		else if(g_PlayerStates[client][fStrafeLoss][i] != 0.0)
		{
			Loss++;
		}
	}
	
	return Gain;
}

public Native_GetStrafeLoss(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	new Gain, Loss;
	
	for(new i = 0; i < g_PlayerStates[client][nStrafes] && i < MAX_STRAFES; i++)
	{
		if(g_PlayerStates[client][fStrafeGain][i] > 50.0)
		{
			Gain++;
		}
		else if(g_PlayerStates[client][fStrafeLoss][i] != 0.0)
		{
			Loss++;
		}
	}
	
	return Loss;
}

public Native_GetStrafePerc(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	new Gain, Loss;
	
	for(new i = 0; i < g_PlayerStates[client][nStrafes] && i < MAX_STRAFES; i++)
	{
		if(g_PlayerStates[client][fStrafeGain][i] > 50.0)
		{
			Gain++;
		}
		else if(g_PlayerStates[client][fStrafeLoss][i] != 0.0)
		{
			Loss++;
		}
	}
	
	return RoundToFloor(100.0*float(Gain)/float(g_PlayerStates[client][nStrafes]));
}

public OnClientPutInServer(client)
{
	g_PlayerStates[client][bHidePanel] = false;
	g_PlayerStates[client][bShowBeam] = false;
	g_PlayerStates[client][bBlockMode] = false;
	g_PlayerStates[client][bOn] = true;
	g_PlayerStates[client][fBlockDistance] = -1.0;
	g_PlayerStates[client][hBeamTimer] = INVALID_HANDLE;
}

public Native_CancelJump(Handle:plugin, numParams)
{
	g_PlayerStates[GetNativeCell(1)][bOn] = true;
}
public OnClientEndTouchZoneType(client, MapZoneType:type)
{
	if (type != ZtStart && type != ZtBonusStart)
		return;
	
	g_PlayerStates[client][bOn] = false;
	
	// Reset stuff
	g_PlayerStates[client][nStrafeDir] = 0;
	g_PlayerStates[client][nStrafes] = 0;
	g_PlayerStates[client][fMaxSpeed] = 0.0;
	g_PlayerStates[client][fStamina] = GetEntPropFloat(client, Prop_Send, "m_flStamina");
	g_PlayerStates[client][fJumpHeight] = 0.0;
	g_PlayerStates[client][nTotalTicks] = 0;
	g_PlayerStates[client][fBlockDistance] = -1.0;
	g_PlayerStates[client][bHasDucked] = false;
	g_PlayerStates[client][bFailedBlock] = false;
	
	if(g_PlayerStates[client][bBlockMode])
	{
		g_PlayerStates[client][fBlockDistance] = GetBlockDistance(client);
	}
	
	
	// Jumpoff origin
	new Float:vOrigin[3];
	GetClientAbsOrigin(client, vOrigin);
	Array_Copy(vOrigin, g_PlayerStates[client][vJumpOrigin], 3);
	
	// Prestrafe
	new Float:vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	g_PlayerStates[client][fPrestrafe] = GetVectorLength(vVelocity);
	
	g_PlayerStates[client][fEdge] = GetEdge(client);
}

public bool:WorldFilter(entity, mask)
{
	// world has entity id 0: if nonzero, tis thing
	if(entity)
		return false;
	
	return true;
}

#define RAYTRACE_Z_DELTA -0.1

Float:GetEdge(client){
	new Float:vOrigin[3], Float:vTraceOrigin[3], Float:vDir[3];
	GetClientAbsOrigin(client, vOrigin);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vDir);
	
	NormalizeVector(vDir, vDir);
	
	vTraceOrigin = vOrigin;
	vTraceOrigin[0] += vDir[0] * 64.0;
	vTraceOrigin[1] += vDir[1] * 64.0;
	vTraceOrigin[2] += RAYTRACE_Z_DELTA;
	
	new Float:vEndPoint[3];
	vEndPoint = vOrigin;
	vEndPoint[0] -= vDir[0] * 32.0;
	vEndPoint[1] -= vDir[1] * 32.0;
	vEndPoint[2] += RAYTRACE_Z_DELTA;
	
	new Handle:hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
	
	if(!TR_DidHit(hTrace))
	{
		CloseHandle(hTrace);
		
		vTraceOrigin[0] += -vDir[1] * 16.0;
		vTraceOrigin[1] += vDir[0] * 16.0;
		
		vEndPoint[0] += -vDir[1] * 16.0;
		vEndPoint[1] += vDir[0] * 16.0;
		
		vEndPoint[0] += vDir[0] * 16.0;
		vEndPoint[1] += vDir[1] * 16.0;
		
		hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
		
		if(!TR_DidHit(hTrace))
		{
			CloseHandle(hTrace);
			
			vTraceOrigin[0] += vDir[1] * 32.0;
			vTraceOrigin[1] += -vDir[0] * 32.0;
			
			vEndPoint[0] += vDir[1] * 32.0;
			vEndPoint[1] += -vDir[0] * 32.0;
			
			hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
		}
	}
	
	if(TR_DidHit(hTrace))
	{
		new Float:vEndPos[3], Float:vNormal[3];
		TR_GetEndPosition(vEndPos, hTrace);
		
		if(GetVectorDistance(vTraceOrigin, vEndPos) != 0.0)
		{
			TR_GetPlaneNormal(hTrace, vNormal);
			
			// correct slopes.
			if(vNormal[2])
			{
				vNormal[2] = 0.0;
				NormalizeVector(vNormal, vNormal);
			}
			
			vOrigin[0] -= vNormal[0] * 16.0;
			vOrigin[1] -= vNormal[1] * 16.0;
			
			if(FloatAbs(vNormal[0]) == 1.0 || FloatAbs(vNormal[1]) == 1.0)
			{
				// The normal is a cardinal direction: simple solution
				if(vNormal[0])
				{
					vEndPos[1] = vOrigin[1];
				}
				else
				{
					vEndPos[0] = vOrigin[0];
				}
			}
			else
			{
				// The normal is noncardinal
				vTraceOrigin = vOrigin;
				vTraceOrigin[0] += vNormal[0] * 64.0;
				vTraceOrigin[1] += vNormal[1] * 64.0;
				vTraceOrigin[2] += RAYTRACE_Z_DELTA;
				
				vEndPoint = vOrigin;
				vEndPoint[0] -= vNormal[0] * 16.0; // You shouldn't be able to jump off over 16 units away from the edge; I don't know why this is needed, but it is.
				vEndPoint[1] -= vNormal[1] * 16.0;
				vEndPoint[2] += RAYTRACE_Z_DELTA;
				
				hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
				
				if(TR_DidHit(hTrace))
				{
					TR_GetEndPosition(vEndPos, hTrace);
				}
			}
			
			// Correct Z -- the trace ray is 2 units lower
			vEndPos[2] = vOrigin[2];
			
			CloseHandle(hTrace);
			
			// Block distance is 0.0625 off, so this is probably 0.03125 off. Consistent with uq_jumpstats's calculation.
			return GetVectorDistance(vEndPos, vOrigin) + 0.03125;
		}
	}
	
	CloseHandle(hTrace);
	
	return -1.0;
}

Float:GetBlockDistance(client){
	new Float:vOrigin[3], Float:vTraceOrigin[3], Float:vDir[3];
	GetClientAbsOrigin(client, vOrigin);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vDir);
	
	NormalizeVector(vDir, vDir);
	
	vTraceOrigin = vOrigin;
	vTraceOrigin[0] += vDir[0] * 64.0;
	vTraceOrigin[1] += vDir[1] * 64.0;
	vTraceOrigin[2] += RAYTRACE_Z_DELTA;
	
	new Float:vEndPoint[3];
	vEndPoint = vOrigin;
	vEndPoint[0] -= vDir[0] * 32.0;
	vEndPoint[1] -= vDir[1] * 32.0;
	vEndPoint[2] += RAYTRACE_Z_DELTA;
	
	new Handle:hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
	
	if(!TR_DidHit(hTrace))
	{
		CloseHandle(hTrace);
		
		vTraceOrigin[0] += -vDir[1] * 16.0;
		vTraceOrigin[1] += vDir[0] * 16.0;
		
		vEndPoint[0] += -vDir[1] * 16.0;
		vEndPoint[1] += vDir[0] * 16.0;
		
		vEndPoint[0] += vDir[0] * 16.0;
		vEndPoint[1] += vDir[1] * 16.0;
		
		hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
		
		if(!TR_DidHit(hTrace))
		{
			CloseHandle(hTrace);
			
			vTraceOrigin[0] += vDir[1] * 32.0;
			vTraceOrigin[1] += -vDir[0] * 32.0;
			
			vEndPoint[0] += vDir[1] * 32.0;
			vEndPoint[1] += -vDir[0] * 32.0;
			
			hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
		}
	}
	
	if(TR_DidHit(hTrace))
	{
		new Float:vBlockStart[3], Float:vBlockEnd[3], Float:vNormal[3];
		TR_GetEndPosition(vBlockStart, hTrace);
		
		if(GetVectorDistance(vTraceOrigin, vBlockStart) > 0.01)
		{
			TR_GetPlaneNormal(hTrace, vNormal);
			
			CloseHandle(hTrace);
			
			vEndPoint = vBlockStart;
			vEndPoint[0] += vNormal[0] * 300.0;
			vEndPoint[1] += vNormal[1] * 300.0;
			
			hTrace = TR_TraceRayFilterEx(vBlockStart, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter);
			
			if(TR_DidHit(hTrace))
			{
				TR_GetEndPosition(vBlockEnd, hTrace);
				
				CloseHandle(hTrace);
				
				// 0.0625 = 1/16 unit error
				return GetVectorDistance(vBlockStart, vBlockEnd) + 0.0625;
			}
			else
			{
				// Trace the other direction
				CloseHandle(hTrace);
				
				decl bool:bLeft;
				
				// rotate normal da way opposite da direction
				if(vNormal[1] > 0)
				{
					if(vDir[0] > vNormal[0])
					{
						bLeft = true;
					}
					else
					{
						bLeft = false;
					}
				}
				else
				{
					if(vDir[0] > vNormal[0])
					{
						bLeft = false;
					}
					else
					{
						bLeft = true;
					}
				}
				
				vDir = vNormal;
				
				new Float:fTempSwap = vDir[0];
				
				vDir[0] = vDir[1];
				vDir[1] = fTempSwap;
				
				if(bLeft)
				{
					vDir[0] = -vDir[0];
				}
				else
				{
					vDir[1] = -vDir[1];
				}
				
				vTraceOrigin = vOrigin;
				vTraceOrigin[0] += vDir[0] * 48.0;
				vTraceOrigin[1] += vDir[1] * 48.0;
				vTraceOrigin[2] += RAYTRACE_Z_DELTA;
				
				vEndPoint = vTraceOrigin;
				vEndPoint[0] += vNormal[0] * 300.0;
				vEndPoint[1] += vNormal[1] * 300.0;
				
				hTrace = TR_TraceRayFilterEx(vTraceOrigin, vEndPoint, MASK_SOLID, RayType_EndPoint, WorldFilter, client);
				
				if(TR_DidHit(hTrace))
				{
					TR_GetEndPosition(vBlockEnd, hTrace);
					
					CloseHandle(hTrace);
					
					// adjust vBlockStart -- the second trace was on a different axis
					vBlockStart[1] += FloatAbs(vNormal[0]) * (vBlockEnd[1] - vBlockStart[1]);
					vBlockStart[0] += FloatAbs(vNormal[1]) * (vBlockEnd[0] - vBlockStart[0]);
					
					// 0.0625 = 1/16 unit error
					return GetVectorDistance(vBlockStart, vBlockEnd) + 0.0625;
				}
			}
		}
	}
	
	
	CloseHandle(hTrace);
	
	return -1.0;
}

GetBlockFailedDistance(client)
{
	new Float:fCurOrigin[3];
	GetClientAbsOrigin(client, fCurOrigin);
	
	g_PlayerStates[client][fHeightDelta] = fCurOrigin[2] - g_PlayerStates[client][vJumpOrigin][2];
	
	fCurOrigin[2] = 0.0;
	
	new Float:v[3];
	Array_Copy(g_PlayerStates[client][vJumpOrigin], v, 3);
	
	v[2] = 0.0;
	
	g_PlayerStates[client][fJumpDistance] = GetVectorDistance(v, fCurOrigin) + 32;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	static Float:vLastOrigin[3];
	static Float:vLastAngles[3];
	static Float:vLastVelocity[3];
	
	
	if(GetEntityFlags(client) & FL_ONGROUND)
	{
		
	}
	else
	{
		//g_PlayerStates[client][bOn] = false;
		
		new Float:vVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
		vVelocity[2] = 0.0;
		if(GetVectorLength(vVelocity) > g_PlayerStates[client][fMaxSpeed])
			g_PlayerStates[client][fMaxSpeed] = GetVectorLength(vVelocity);
		
		new Float:vOrigin[3];
		GetClientAbsOrigin(client, vOrigin);
		if(vOrigin[2] - g_PlayerStates[client][vJumpOrigin][2] > g_PlayerStates[client][fJumpHeight])
			g_PlayerStates[client][fJumpHeight] = vOrigin[2] - g_PlayerStates[client][vJumpOrigin][2];
		
		// Record the failed distance, but since it will trigger if you duck late, only save it if it's certain that the player will not land
		if(g_PlayerStates[client][bBlockMode] &&
		!g_PlayerStates[client][bFailedBlock] &&
		vOrigin[2] <= g_PlayerStates[client][vJumpOrigin][2] + 1.0)
		{
			GetBlockFailedDistance(client);
		}
		
		// Check if the player is still capable of landing
		if(g_PlayerStates[client][bBlockMode] && !g_PlayerStates[client][bFailedBlock] && 
		(buttons & IN_DUCK && vOrigin[2] <= g_PlayerStates[client][vJumpOrigin][2] + 1.0 || // You land at 0.79 elevation when ducking
		!(buttons & IN_DUCK) && vOrigin[2] <= g_PlayerStates[client][vJumpOrigin][2] - 9.5)) // Ducking increases your origin by 8.5; you land at 0.79 units elevation when ducking, so around 9.5
		{
			g_PlayerStates[client][bDuck] = bool:(buttons & IN_DUCK);
			g_PlayerStates[client][bFailedBlock] = true;
		}
		
		if(buttons & IN_DUCK && vOrigin[2] <= g_PlayerStates[client][vJumpOrigin][2] + 10.0) // Ducking increases your origin by 8.5; you land at 1.47 units elevation when not ducking, so around 10
		{
			g_PlayerStates[client][bHasDucked] = true;
		}
	}
	
	if(g_PlayerStates[client][bOn])
	{
		GetClientAbsOrigin(client, vLastOrigin);
		GetClientAbsAngles(client, vLastAngles);
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vLastVelocity);
		return;
	}
	
	if(g_PlayerStates[client][nStrafes] >= MAX_STRAFES)
	{
		GetClientAbsOrigin(client, vLastOrigin);
		GetClientAbsAngles(client, vLastAngles);
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vLastVelocity);
		return;
	}
	
	new nButtonCount;
	if(buttons & IN_MOVELEFT)
		nButtonCount++;
	if(buttons & IN_MOVERIGHT)
		nButtonCount++;
	if(buttons & IN_FORWARD)
		nButtonCount++;
	if(buttons & IN_BACK)
		nButtonCount++;
	
	if(nButtonCount == 1)
	{
		if(g_PlayerStates[client][nStrafeDir] != 1 && buttons & IN_MOVELEFT)
		{
			g_PlayerStates[client][cStrafeKey][g_PlayerStates[client][nStrafes]] = 'A';
			g_PlayerStates[client][nStrafeDir] = 1;
			g_PlayerStates[client][nStrafes]++;
		}
		else if(g_PlayerStates[client][nStrafeDir] != 2 && buttons & IN_MOVERIGHT)
		{
			g_PlayerStates[client][cStrafeKey][g_PlayerStates[client][nStrafes]] = 'D';
			g_PlayerStates[client][nStrafeDir] = 2;
			g_PlayerStates[client][nStrafes]++;
		}
		else if(g_PlayerStates[client][nStrafeDir] != 3 && buttons & IN_FORWARD)
		{
			g_PlayerStates[client][cStrafeKey][g_PlayerStates[client][nStrafes]] = 'W';
			g_PlayerStates[client][nStrafeDir] = 3;
			g_PlayerStates[client][nStrafes]++;
		}
		else if(g_PlayerStates[client][nStrafeDir] != 4 && buttons & IN_BACK)
		{
			g_PlayerStates[client][cStrafeKey][g_PlayerStates[client][nStrafes]] = 'S';
			g_PlayerStates[client][nStrafeDir] = 4;
			g_PlayerStates[client][nStrafes]++;
		}
	}
	
	if(g_PlayerStates[client][nStrafes] > 0)
	{
		new Float:fVelDelta = GetSpeed(client) - GetVSpeed(vLastVelocity);
		
		g_PlayerStates[client][nTotalTicks]++;
		g_PlayerStates[client][nStrafeTicks][g_PlayerStates[client][nStrafes] - 1]++;
		
		if(fVelDelta > 0.0)
		{
			g_PlayerStates[client][fStrafeGain][g_PlayerStates[client][nStrafes] - 1] += fVelDelta;
			
			g_PlayerStates[client][nStrafeTicksSynced][g_PlayerStates[client][nStrafes] - 1]++;
		}
		else
		{
			g_PlayerStates[client][fStrafeLoss][g_PlayerStates[client][nStrafes] - 1] += fVelDelta;
		}
	}
	
	GetClientAbsOrigin(client, vLastOrigin);
	GetClientAbsAngles(client, vLastAngles);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vLastVelocity);
}

public OnClientStartTouchZoneType(client, MapZoneType:type)
{
	if (type != ZtEnd && type != ZtBonusEnd)
		return;
	
	g_PlayerStates[client][bOn] = true;
	
	new Float:fSync;
	
	new Gain, Loss;
	
	for(new i = 0; i < g_PlayerStates[client][nStrafes] && i < MAX_STRAFES; i++)
	{
		fSync += g_PlayerStates[client][nStrafeTicksSynced][i];
		if(g_PlayerStates[client][fStrafeGain][i] > 50.0)
		{
			Gain++;
		}
		else if(g_PlayerStates[client][fStrafeLoss][i] != 0.0)
		{
			Loss++;
		}
	}
	
	fSync /= g_PlayerStates[client][nTotalTicks];
	fSync *= 100;
	
	PrintToChatAll("%N - Count: %d Sync:%.2f Prestrafe:%.2f Gain:%d Loss:%d Perc:%d", client, 
	g_PlayerStates[client][nStrafes], fSync, g_PlayerStates[client][fPrestrafe], Gain, Loss, RoundToFloor(100.0*float(Gain)/float(g_PlayerStates[client][nStrafes])));
}

public StatsMenuHandler(Handle:hMenu, MenuAction:action, param1, param2) 
{
}

Float:GetSpeed(client)
{
	new Float:vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	vVelocity[2] = 0.0;
	
	return GetVectorLength(vVelocity); 
}

Float:GetVSpeed(Float:v[3])
{
	new Float:vVelocity[3];
	vVelocity = v;
	vVelocity[2] = 0.0;
	
	return GetVectorLength(vVelocity);
}