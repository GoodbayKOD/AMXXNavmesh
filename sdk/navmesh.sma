#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <reapi>
#include <xs>

// libraries used:
// https://github.com/s1lentq/ReGameDLL_CS/blob/f57d28fe721ea4d57d10c010d15d45f05f2f5bad/regamedll/game_shared/bot/nav_file.cpp
// https://github.com/s1lentq/ReGameDLL_CS/blob/f57d28fe721ea4d57d10c010d15d45f05f2f5bad/regamedll/game_shared/bot/nav_file.h
// https://github.com/s1lentq/ReGameDLL_CS/blob/f57d28fe721ea4d57d10c010d15d45f05f2f5bad/regamedll/game_shared/bot/nav.h

// 21/12/2022 02:41 a.m
// not yet functional
// I continue to make progress in obtaining data from the archive
// I am experiencing problems getting the file data from the m_extent forward

// 27/12/2022 20:05 p.m.
// not yet functional
// I am experiencing problems in the area loop, out of nowhere it starts getting wrong values

// Necessary defines
#define TASK_DRAWNAV       		32423
#define MAX_AREAS			1320

#define NAV_MAGIC_NUMBER		-17958194 // (0xFEEDFACE)
#define NAV_VERSION			5

// Macros
#define check_area(%1)			(0 <= %1 <= MAX_AREAS)

// Enumerators

// Defines possible ways to move from one area to another
// NOTE: First 4 directions MUST match NavDirType
enum _:m_hNavTraverseType
{
	GO_NORTH = 0,
	GO_EAST,
	GO_SOUTH,
	GO_WEST,
	GO_LADDER_UP,
	GO_LADDER_DOWN,
	GO_JUMP
}

enum _:m_hNavCornerType
{
	NORTH_WEST = 0,
	NORTH_EAST,
	SOUTH_EAST,
	SOUTH_WEST
}

enum _:m_hNavRelativeDirType
{
	FORWARD = 0,
	RIGHT,
	BACKWARD,
	LEFT,
	UP,
	DOWN
}

enum _:m_hHash
{
	H_NEXT = 0,
	H_PREV
}

enum _:m_hNavErrorType
{
	NAV_OK,
	NAV_CANT_ACCESS_FILE,
	NAV_INVALID_FILE,
	NAV_BAD_FILE_VERSION,
	NAV_CORRUPT_DATA
}

enum _:m_hNavAttributeType
{
	NAV_NONE,
	NAV_CROUCH, 	// must crouch to use this node/area
	NAV_JUMP, 		// must jump to traverse this area
	NAV_PRECISE, 	// do not adjust for obstacles, just move along area
	NAV_NO_JUMP 	// inhibit discontinuity jumping
}

new const GameRules_AreaAttribute[m_hNavAttributeType][] =
{
	"NONE",
	"CROUCH",
	"JUMP",
	"PRECISE",
	"NO-JUMP"
}

enum _:m_hNavDirType
{
	NORTH = 0,
	EAST,
	SOUTH,
	WEST
}

new const GameRules_AreaDirection[m_hNavDirType][] =
{
	"North",
	"East",
	"South",
	"West"
}

// Vectors
new Float:g_vOrigin[3], Float:g_vStart[3], Float:g_vEnd[3], Float:g_vGoal[3], Float:g_vPlane[3], Float:g_vVelocity[3], 
Float:g_vOffset[3], Float:g_vGoalAngle[3], Float:g_vAngles[3], Float:g_vAnchor[3];
new Float:g_vForward[3], Float:g_vRight[3], Float:g_vUp[3], Float:g_vDirection[3], Float:g_vDestine[3];
new Float:g_vNull[3] = {0.000000, 0.000000, 0.000000};

enum _:m_hExtent
{
	EX_LOW = 0,
	EX_HIGH
}
new Float:g_vExtent[m_hExtent][3], Float:g_vCenter[3];
new Float:g_fNeZ, Float:g_fSwZ;

new g_hMenu;
new g_pLaserBeam;

new Array:g_aAreaID, Array:g_aAreaNextID, Array:g_aAttributeFlags, Array:g_aApproachCount, Array:g_aCenter, Array:g_aExtent, Array:g_aNorthEast, Array:g_aSouthWest;
new g_szMapName[32];

public plugin_precache()
{
	// Create arrays
	g_aAreaID 		= ArrayCreate();
	g_aAreaNextID 		= ArrayCreate();
	g_aAttributeFlags 	= ArrayCreate();
	g_aApproachCount	= ArrayCreate();
	g_aCenter		= ArrayCreate(64);
	g_aExtent 		= ArrayCreate(82);
	g_aNorthEast		= ArrayCreate(12);
	g_aSouthWest		= ArrayCreate(12);

	// Get mapname
	get_mapname(g_szMapName, charsmax(g_szMapName));
	strtolower(g_szMapName);

	Navmesh_LoadMap();
}

public plugin_init()
{
	register_plugin("Navmesh", "1.0", "Goodbay");
	register_concmd("nav_area_info", "cmd_areainfo");
}

public cmd_areainfo(const pPlayer, level, cid)
{
    	// Get area param
	new iArea = read_argv_int(1);

	// Invalid area
	if(!check_area(iArea))
	{
		// Print & return
		console_print(pPlayer, "[NavMesh] (%d) No es un area valida", iArea);
		return 0;
	}

	// Get center
	Navmesh_GetCenter(iArea);

	// Get extent
	Navmesh_GetExtent(iArea, m_hExtent:EX_LOW);
	Navmesh_GetExtent(iArea, m_hExtent:EX_HIGH);

	// Get corners
	g_fNeZ = Navmesh_GetCornerZ(iArea, m_hNavCornerType:NORTH_EAST);
	g_SwZ = Navmesh_GetCornerZ(iArea, m_hNavCornerType:SOUTH_WEST);

	// Print
	console_print(pPlayer, "^n=======================^nm_id: %d^nm_nextID: %d^nm_attributeFlags: %d", ArrayGetCell(g_aAreaID, iArea), ArrayGetCell(g_aAreaNextID, iArea), 
	ArrayGetCell(g_aAttributeFlags, iArea));

	console_print(pPlayer, "m_center.x: %.6f^nm_center.y: %.6f^nm_center.z: %.6f", g_vCenter[0], g_vCenter[1], g_vCenter[2]);
	console_print(pPlayer, "m_extent.lo.x: %.6f^nm_extent.lo.y: %.6f^nm_extent.lo.z: %.6f^nm_extent.hi.x: %.6f", g_vExtent[EX_LOW][0], g_vExtent[EX_LOW][1], 
	g_vExtent[EX_LOW][2], g_vExtent[EX_HIGH][0]);

	console_print(pPlayer, "m_extent.hi.y: %.6f^nm_extent.hi.z: %.6f", g_vExtent[EX_HIGH][1], g_vExtent[EX_HIGH][2]);
	console_print(pPlayer, "m_neZ: %.6f^nm_swZ: %.6f^n=======================", g_fNeZ, g_fSwZ);
	return 1;
}

/*  Navmesh Functions   */

public Navmesh_LoadSpot(const iFile)
{
	static iSpotID, iSpotFlags, Float:vPos[3];

	fread(iFile, iSpotID, BLOCK_INT);
	fread_blocks(iFile, _:vPos, 3, BLOCK_INT);
	fread(iFile, iSpotFlags, BLOCK_CHAR);

	server_print("spotID: %d", iSpotID);
	server_print("spotPosition: %.6f %.6f %.6f", vPos[0], vPos[1], vPos[2]);
	server_print("spotFlags: %d", iSpotFlags);
}

public Navmesh_LoadMap()
{
	new szPath[PLATFORM_MAX_PATH];
	formatex(szPath, charsmax(szPath), "maps/%s.nav", g_szMapName);

	// File does'nt exists?
	if(!file_exists(szPath))
	{
		// Print error & return
		server_print("[NavMesh] Can't access to the navigation file: %s", szPath);
		return NAV_CANT_ACCESS_FILE;
	}

	// Open .nav file
	new iFile = fopen(szPath, "rt");

	if(!iFile)
		return NAV_CANT_ACCESS_FILE;

	// Some arrays and vars to storage info
	new iResult, iMagic, iVersion, iSaveBSPSize, iEntries, iLen, szPlaceName[64], iArea, i, iAreaCounts;

	// check magic number
	iResult = fread(iFile, iMagic, BLOCK_INT);

	if(!iResult || iMagic != NAV_MAGIC_NUMBER)
	{
		server_print("[NavMesh ERROR] Invalid navigation file '%s'.", szPath);
		return NAV_INVALID_FILE;
	}

	// read file version number
	iResult = fread(iFile, iVersion, BLOCK_INT);

	if(!iResult || iVersion > NAV_VERSION)
	{
		server_print("[NavMesh ERROR] Unknown navigation file version.");
		return NAV_BAD_FILE_VERSION;
	}

	if(iVersion >= 4)
	{
		// get size of source bsp file and verify that the bsp hasn't changed
		fread(iFile, iSaveBSPSize, BLOCK_INT);

		new szBspFilename[42];
		formatex(szBspFilename, charsmax(szBspFilename), "maps/%s.bsp", g_szMapName);

		// verify size
		if(filesize(szBspFilename) != iSaveBSPSize)
		{
			// this nav file is out of date for this bsp file
			server_print("[NavMesh WARNING] The AI navigation data is from a different version of this map.^nThe CPU players will likely not perform well.");
		}
	}
	
	fread(iFile, iEntries, BLOCK_SHORT);

	// Map entries
	for(i = 0; i < iEntries; i++)
	{
		fread(iFile, iLen, BLOCK_SHORT);
		fread_blocks(iFile, _:szPlaceName, iLen, BLOCK_CHAR);

		server_print("Place #%d: %s", i, szPlaceName);
	}

    	// Print basic info
	server_print("^nNavMesh Info Data - navmesh.amxx^nMagic Number: %d^nVersion: %d^nBSPSize: %d^nEntries: %d^n[", iMagic, iVersion, iSaveBSPSize, iEntries);

	fread(iFile, iAreaCounts, BLOCK_INT);
	server_print("]^nTotal Map Areas: %d", iAreaCounts);
	log_amx("TOTAL AREAS %d", iAreaCounts);

	for(iArea = 0; iArea < iAreaCounts; iArea++)
	{
		server_print("^n^nArea %d", iArea);

		if(!Navmesh_LoadArea(iFile, iVersion, iArea))
			break;
	}

	fclose(iFile);
	return NAV_OK;
}

public Navmesh_LoadArea(const iFile, const iVersion, const iArea)
{
	new Float:vVector[6], iID, iFlags, szFormat[124], Float:fCorner[2];
	new i, d, h, a, e, s, t, iCount, iConnect, iHidingSpots, iSpots, iApproach, iType, iEncounter, iDir, iOrder, iEntry;

	// load ID
	fread(iFile, iID, BLOCK_INT);
	GameArray_Update(g_aAreaID, iID);
	log_amx("Last Area: %d | ID: %d | NextID: %d", iArea, iID, iID + 1);

	// update nextID to avoid collisions
	GameArray_Update(g_aAreaNextID, iID + 1);

	// load attribute flags
	fread(iFile, iFlags, BLOCK_CHAR);
	GameArray_Update(g_aAttributeFlags, iFlags);
	log_amx("Flag: %s", (nullptr < iFlags > m_hNavAttributeType) ? "ERROR" : GameRules_AreaAttribute[iFlags]);

	// load extent of area
	fread_blocks(iFile, _:vVector, 6, BLOCK_INT);

	// Convert into string
	formatex(szFormat, charsmax(szFormat), "%.6f %.6f %.6f %.6f %.6f %.6f", vExtent[0], vExtent[1], vExtent[2], vExtent[3], vExtent[4], vExtent[5]);
	ArrayPushString(g_aExtent, szFormat);
	log_amx("Extent: lo %.6f %.6f %.6f hi %.6f %.6f %.6f", vVector[0], vVector[1], vVector[2], vVector[3], vVector[4], vVector[5]);

	// update center
	Navmesh_UpdateCenter(vVector);

	// load heights of implicit corners
	fread_blocks(iFile, _:fCorner, 2, BLOCK_INT);

	// convert into string and save
	float_to_str(fCorner[0], szFormat, charsmax(szFormat));
	ArrayPushString(g_aNorthEast, szFormat);
	float_to_str(fCorner[1], szFormat, charsmax(szFormat));
	ArrayPushString(g_aSouthWest, szFormat);

	if(equal(g_szMapName, "colapse") && iArea == 15)
		log_amx("Flags: %d | m_neZ: %.6f^nm_swZ: %.6f", iFlags, fCorner[0], fCorner[1]);

	for(d = 0; d < m_hNavDirType; d++)
	{
		// Reset
		iCount = 0;

		// load number of connections for this direction
		fread(iFile, iCount, BLOCK_INT);
		log_amx("Connections: %d - Direction: %s", iCount, GameRules_AreaDirection[d]);

		for(i = 0; i < iCount; i++)
			fread(iFile, iConnect, BLOCK_INT);
	}

	fread(iFile, iHidingSpots, BLOCK_CHAR);
	log_amx("hidingSpotCount: %d", iHidingSpots);

	if(iVersion == 1)
	{
		// load simple vector array
		for(h = 0; h < iHidingSpots; h++)
			fread_blocks(iFile, _:vVector, 3, BLOCK_INT);
	}
	else
	{
		// load HidingSpot objects for this area
		for(h = 0; h < iHidingSpots; h++)
		{
			// create new hiding spot and put on master list
			Navmesh_LoadSpot(iFile);
		}
	}

	// Load number of approach areas
	fread(iFile, iCount, BLOCK_CHAR);
	ArrayPushCell(g_aApproachCount, iCount);
	log_amx("m_approachCount: %d", iCount);

	// load approach area info (IDs)
	for(a = 0; a < iCount; a++)
	{
		fread(iFile, iApproach, BLOCK_INT);
		fread(iFile, iApproach, BLOCK_INT);
		fread(iFile, iType, BLOCK_CHAR);

		fread(iFile, iApproach, BLOCK_INT);
		fread(iFile, iType, BLOCK_CHAR);
	}

	// Load encounter paths for this area
	fread(iFile, iCount, BLOCK_INT);
	log_amx("encounter: %d", iCount);

	if(iVersion < 3)
	{
		// old data, read and discard
		for(e = 0; e < iCount; e++)
		{
			fread(iFile, iEncounter, BLOCK_INT);
			fread(iFile, iEncounter, BLOCK_INT);

			fread_blocks(iFile, _:vVector, 3, BLOCK_INT);
			fread_blocks(iFile, _:vVector, 3, BLOCK_INT);

			// read list of spots along this path
			fread(iFile, iSpots, BLOCK_CHAR);
			log_amx("Spots: %d", iSpots);

			for(s = 0; s < iSpots; s++)
			{
				fread_blocks(iFile, _:vVector, 3, BLOCK_INT);
				fread_blocks(iFile, _:vVector, 0, BLOCK_INT);
			}
		}

		return 1;
	}

	for(e = 0; e < iCount; e++)
	{
		fread(iFile, iEncounter, BLOCK_INT);
		fread(iFile, iDir, BLOCK_CHAR);

		fread(iFile, iEncounter, BLOCK_INT);
		fread(iFile, iDir, BLOCK_CHAR);

		// read list of spots along this path
		fread(iFile, iSpots, BLOCK_CHAR);
		log_amx("Spots 2: %d", iSpots);

		for(s = 0; s < iSpots; s++)
		{
			fread(iFile, iOrder, BLOCK_INT);
			fread(iFile, t, BLOCK_CHAR);
		}
	}

	if(iVersion >= NAV_VERSION)
	{
		// Load Place data
		fread(iFile, iEntry, BLOCK_SHORT);
		log_amx("Entry: %d", iEntry);
	}

	return 1;
}

/*  Main Stocks   */

stock Navmesh_ConvertExtent(Float:vExtent[], szOutput[], len)
{
	// Convert into string
	formatex(szOutput, len, "%.6f %.6f %.6f %.6f %.6f %.6f", vExtent[0], vExtent[1], vExtent[2], vExtent[3], vExtent[4], vExtent[5]);
}

stock Navmesh_UpdateCenter(const Float:vExtent[6])
{
	new szCenter[64];

	g_vCenter[0] = ((vExtent[0] + vExtent[3]) / 2.0);
	g_vCenter[1] = ((vExtent[1] + vExtent[4]) / 2.0);
	g_vCenter[2] = ((vExtent[2] + vExtent[5]) / 2.0);

	vec_to_str(g_vCenter, szCenter, charsmax(szCenter));
	ArrayPushString(g_aCenter, szCenter);
}

stock Navmesh_GetExtent(const iArea, const m_hExtent:iExtent)
{
	if(!check_area(iArea))
		return 0;

	new szValue[72], szPos[6][18];
	ArrayGetString(g_aExtent, iArea, szValue, charsmax(szValue));

	if(szValue[0] == EOS)
		return 0;

	parse(szValue, szPos[0], charsmax(szPos[]), szPos[1], charsmax(szPos[]), szPos[2], charsmax(szPos[]), szPos[3], charsmax(szPos[]), szPos[4], charsmax(szPos[]), 
	szPos[5], charsmax(szPos[]));

	g_vExtent[iExtent][0] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[0]) : str_to_float(szPos[3]);
	g_vExtent[iExtent][1] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[1]) : str_to_float(szPos[4]);
	g_vExtent[iExtent][2] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[2]) : str_to_float(szPos[5]);
	return 1;
}

stock Navmesh_GetCenter(const iArea)
{
	if(!check_area(iArea))
		return 0;

	new szCenter[64], szPos[3][18];
	ArrayGetString(g_aCenter, iArea, szCenter, charsmax(szCenter));

	if(szCenter[0] == EOS)
		return 0;

	parse(szCenter, szPos[0], charsmax(szPos[]), szPos[1], charsmax(szPos[]), szPos[2], charsmax(szPos[]));
	str_to_vec(szPos, g_vCenter);
	return 1;
}

stock Float:Navmesh_GetCornerZ(const iArea, const m_hNavCornerType:iCorner)
{
	new szCorner[16], Float:fCornerZ;

	if(!(BIT(iCorner) & (BIT(NORTH_EAST) | BIT(SOUTH_EAST))))
		return 0.0;

	new Array:aCorner = (iCorner == NORTH_EAST) ? g_aNorthEast : g_aSouthWest;

	ArrayGetString(aCorner, iArea, szCorner, charsmax(szCorner));

	if(szCorner[0] == EOS)
		return 0.0;

	return str_to_float(szCorner);
}

stock vec_to_str(Float:vVector[], szOutput[], len)
	formatex(szOutput, len, "%.6f %.6f %.6f", vVector[0], vVector[1], vVector[2]);

stock str_to_vec(const szValue[][], Float:vOutput[])
{
	vOutput[0] = str_to_float(szValue[0]);
	vOutput[1] = str_to_float(szValue[1]);
	vOutput[2] = str_to_float(szValue[2]);
}

stock GameArray_Update(const Array:aArray, const iValue)
    return ArrayPushCell(aArray, iValue);
