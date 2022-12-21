#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <reapi>
#include <xs>

// 21/12/2022 02:41 a.m
// not yet functional
// I continue to make progress in obtaining data from the archive
// I am experiencing problems getting the file data from the m_extent forward
// nav_file.cpp https://github.com/s1lentq/ReGameDLL_CS/blob/f57d28fe721ea4d57d10c010d15d45f05f2f5bad/regamedll/game_shared/bot/nav_file.cpp#L754

// Necessary defines
#define TASK_DRAWNAV       		32423
#define MAX_AREAS				1320
#define NAV_MAGIC_NUMBER		0xFEEDFACE

// Macros
#define is_valid_area(%1)				(-1 <= %1 < MAX_AREAS)

// Enumerators
enum _:m_hNavAttributeType
{
	NAV_CROUCH  = 0x01, 	// must crouch to use this node/area
	NAV_JUMP    = 0x02, 	// must jump to traverse this area
	NAV_PRECISE = 0x04, 	// do not adjust for obstacles, just move along area
	NAV_NO_JUMP = 0x08 		// inhibit discontinuity jumping
}

enum _:m_hNavDirType
{
	NORTH = 0,
	EAST,
	SOUTH,
	WEST
}

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

enum _:m_hExtent
{
	EX_LOW = 0,
	EX_HIGH
}

new g_hMenu;
new g_pLaserBeam;

new Array:g_aAreaID, Array:g_aAreaNextID, Array:g_aAttributeFlags, Array:g_aCenter, Array:g_aExtent, Array:g_aNorthEast, Array:g_aSouthWest;
new g_szMapName[32];

public plugin_precache()
{
	// Create arrays
	g_aAreaID 			= ArrayCreate();
	g_aAreaNextID 		= ArrayCreate();
	g_aAttributeFlags 	= ArrayCreate();
	g_aCenter			= ArrayCreate(64);
	g_aExtent 			= ArrayCreate(72);
	g_aNorthEast		= ArrayCreate(12);
	g_aSouthWest		= ArrayCreate(12);
    
	// Get mapname
	get_mapname(g_szMapName, charsmax(g_szMapName));
	strtolower(g_szMapName);
    
    // Load nav
	LoadNavigationMap();
}

public plugin_init()
{
	register_plugin("Navmesh", "1.0", "Goodbay");
	register_concmd("nav_area_info", "cmd_areainfo");
}

public cmd_areainfo(const pPlayer, level, cid)
{
	new iArea = read_argv_int(1);
    
	// Invalid area
	if(!is_valid_area(iArea))
	{
		// Print & return
		console_print(pPlayer, "[NavMesh] (%d) No es un area valida", iArea);
		return 0;
	}
    
	new Float:vCenter[3], Float:vLow[3], Float:vHigh[3];
    
	// Get center
	Navmesh_GetCenter(iArea, vCenter);
    
	// Get extent
	Navmesh_GetExtent(iArea, m_hExtent:EX_LOW, vLow);
	Navmesh_GetExtent(iArea, m_hExtent:EX_HIGH, vHigh);
    
	// Get corners
	new Float:fNeZ = Navmesh_GetCornerZ(iArea, m_hNavCornerType:NORTH_EAST);
	new Float:fSwZ = Navmesh_GetCornerZ(iArea, m_hNavCornerType:SOUTH_WEST);
    
	// Prints
	console_print(pPlayer, "^n=======================^nm_id: %d^nm_nextID: %d^nm_attributeFlags: %d", ArrayGetCell(g_aAreaID, iArea), ArrayGetCell(g_aAreaNextID, iArea), 
	ArrayGetCell(g_aAttributeFlags, iArea));
    
	console_print(pPlayer, "m_center.x: %.6f^nm_center.y: %.6f^nm_center.z: %.6f", 
	ArrayGetCell(g_aAreaID, iArea), ArrayGetCell(g_aAreaNextID, iArea), ArrayGetCell(g_aAttributeFlags, iArea), vCenter[0], vCenter[1], vCenter[2]);
    
	console_print(pPlayer, "m_extent.lo.x: %.6f^nm_extent.lo.y: %.6f^nm_extent.lo.z: %.6f^nm_extent.hi.x: %.6f^nm_extent.hi.y: %.6f", vLow[0], vLow[1], vLow[2],
	vHigh[0], vHigh[1]);
    
	console_print(pPlayer, "m_extent.hi.z: %.6f^nm_neZ: %.6f^nm_swZ: %.6f^n=======================", vHigh[2], fNeZ, fSwZ);
	return 1;
}
public LoadNavigationMap()
{
	new szPath[64];
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
    
	// Some arrays and vars to storage info
	new iMagic, iVersion, iBSPSize, iEntries, iLen, szPlaceName[64], iAreas, i;
    
	// Get basic info
	fread(iFile, iMagic, BLOCK_INT);
	fread(iFile, iVersion, BLOCK_INT);
	fread(iFile, iBSPSize, BLOCK_INT);
	fread(iFile, iEntries, BLOCK_SHORT);
	
	// Print basic info
	server_print("^nNavMesh Info Data - navmesh.amxx^nMagic Number: %d^nVersion: %d^nBSPSize: %d^nEntries: %d^n[", iMagic, iVersion, iBSPSize, iEntries);
    
	// Map entries
	for(i = 0; i < iEntries; i++)
	{
		fread(iFile, iLen, BLOCK_SHORT);
		fread_blocks(iFile, _:szPlaceName, iLen, BLOCK_CHAR);
		server_print("Place #%d: %s", i, szPlaceName);
	}
    
	fread(iFile, iAreas, BLOCK_INT);
	server_print("]^nTotal Map Areas: %d", iAreas);
    
	new Float:vExtent[6], iID, iFlags, szExtent[72], szNeZ[12], szSwZ[12];
    
	// load ID
	fread(iFile, iID, BLOCK_INT);
	GameArray_Update(g_aAreaID, iID);
	server_print("m_id: %d", iID);
    
	// update nextID to avoid collisions
	GameArray_Update(g_aAreaNextID, iID + 1);
	server_print("m_nextID: %d", iID + 1);
    
	// load attribute flags
	fread(iFile, iFlags, BLOCK_CHAR);
	GameArray_Update(g_aAttributeFlags, iFlags);
	server_print("m_attributeFlags: %d", iFlags);
    
	// load extent of area
	fread_blocks(iFile, _:szExtent, charsmax(szExtent), BLOCK_CHAR);
	ArrayPushString(g_aExtent, szExtent);
    server_print("m_extent: %s^n", szExtent);
    
	// update centroid
	Navmesh_UpdateCentroID(i);
    
	// load heights of implicit corners
	fread_blocks(iFile, _:szNeZ, charsmax(szNeZ), BLOCK_CHAR);
	fread_blocks(iFile, _:szSwZ, charsmax(szSwZ), BLOCK_CHAR);
	ArrayPushString(g_aNorthEast, szNeZ);
	ArrayPushString(g_aSouthWest, szSwZ);
    
    server_print("m_neZ: %s^n", szNeZ);
	server_print("m_swZ: %s^n", szSwZ);
    
	fclose(iFile);
	return 1;
}

stock Navmesh_ConvertExtent(Float:vExtent[], szOutput[], len)
{
	// Convert into string
	formatex(szOutput, len, "%s %s %s %s %s %s", vExtent[0], vExtent[1], vExtent[2], vExtent[3], vExtent[4], vExtent[5]);
	server_print("Extent: %s^n", szOutput);
}

stock Navmesh_UpdateCentroID(const iArea)
{
	if(!is_valid_area(iArea))
		return 0;
        
	new Float:vLow[3], Float:vHigh[3], Float:vCenter[3];
	new szCenter[64];
    
	Navmesh_GetExtent(iArea, m_hExtent:EX_LOW, vLow);
	Navmesh_GetExtent(iArea, m_hExtent:EX_HIGH, vHigh);
    
	vCenter[0] = ((vLow[0] + vHigh[0]) / 2.0);
	vCenter[1] = ((vLow[1] + vHigh[1]) / 2.0);
	vCenter[2] = ((vLow[2] + vHigh[2]) / 2.0);
    
	vec_to_str(vCenter, szCenter, charsmax(szCenter));
	ArrayPushString(g_aCenter, szCenter);
	return 1;
}

stock Navmesh_GetExtent(const iArea, const m_hExtent:iExtent, Float:vOutput[])
{
	if(!is_valid_area(iArea))
		return 0;
        
	new szExtent[72], szPos[6][18];
	ArrayGetString(g_aExtent, iArea, szExtent, charsmax(szExtent));
    
	if(szExtent[0] == EOS)
		return 0;
        
	parse(szExtent, szPos[0], charsmax(szPos[]), szPos[1], charsmax(szPos[]), szPos[2], charsmax(szPos[]), szPos[3], charsmax(szPos[]), szPos[4], charsmax(szPos[]), 
	szPos[5], charsmax(szPos[]));
    
	vOutput[0] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[0]) : str_to_float(szPos[3]);
	vOutput[1] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[1]) : str_to_float(szPos[4]);
	vOutput[2] = (iExtent == m_hExtent:EX_LOW) ? str_to_float(szPos[2]) : str_to_float(szPos[5]);
    
	return 1;
}

stock Navmesh_GetCenter(const iArea, Float:vOutput[])
{
	if(!is_valid_area(iArea))
		return 0;
        
	new szCenter[64], szPos[3][18];
    
	ArrayGetString(g_aCenter, iArea, szCenter, charsmax(szCenter));
    
	if(szCenter[0] == EOS)
		return 0;
        
	parse(szCenter, szPos[0], charsmax(szPos[]), szPos[1], charsmax(szPos[]), szPos[2], charsmax(szPos[]));
	str_to_vec(szPos, vOutput);
    
	return 1;
}

stock Float:Navmesh_GetCornerZ(const iArea, const m_hNavCornerType:iCorner)
{
	new szCorner[16];
    
	switch(iCorner)
	{
		case NORTH_EAST:
			ArrayGetString(g_aNorthEast, iArea, szCorner, charsmax(szCorner));
		case SOUTH_WEST:
			ArrayGetString(g_aSouthWest, iArea, szCorner, charsmax(szCorner));
		default:
			return 0.0;
	}
    
	if(szCorner[0] == EOS)
		return 0.0;
        
	return str_to_float(szCorner);
}

stock vec_to_str(const Float:vVector[], szOutput[], len)
{
	new szVector[3][18];
    
	float_to_str(vVector[0], szVector[0], charsmax(szVector));
	float_to_str(vVector[1], szVector[1], charsmax(szVector));
	float_to_str(vVector[2], szVector[2], charsmax(szVector));
    
	formatex(szOutput, len, "%s %s %s", szVector[0], szVector[1], szVector[2]);
}

stock str_to_vec(const szValue[][], Float:vOutput[])
{
	vOutput[0] = str_to_float(szValue[0]);
	vOutput[1] = str_to_float(szValue[1]);
	vOutput[2] = str_to_float(szValue[2]);
}

stock GameArray_Update(const Array:aArray, const iValue)
    return ArrayPushCell(aArray, iValue);
