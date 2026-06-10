# File Naming Conventions

## Standardized Image Names

Images renamed to encode metadata for AI-ready dataset organization:

**Format:**
```
{Species_name}_{TrayType}tray_Y{Year}_{FirstIndividualID}-{LastIndividualID}.{ext}
```

**Components:**
- `Species_name` - Genus_species with underscores replacing spaces
- `TrayType` - Single letter (A, B, C, etc.)
- `Year` - Four-digit collection year
- `FirstIndividualID` - Full NEON ID of first specimen
- `LastIndividualID` - Full NEON ID of last specimen (omitted if single specimen)
- `ext` - File extension (JPG, PNG, etc.)

**Examples:**
```
Amara_tenax_Btray_Y2018_NEON.BET.D09.002825-NEON.BET.D09.003611.png
Carabus_goryi_Atray_Y2020_NEON.BET.D15.001234.PNG
Pterostichus_melanarius_Ctray_Y2019_NEON.BET.D03.005678-NEON.BET.D03.005702.png
```

## Individual ID Format

NEON individual identifiers follow standardized structure enabling automated parsing:

**Format:** `NEON.BET.D{DomainID}.{NumericID}`

**Components:**
- `NEON` - Network identifier
- `BET` - Beetle (ground beetle) product code
- `D{DomainID}` - Two-digit domain identifier (D01-D20)
- `{NumericID}` - Six-digit numeric identifier unique within domain

**Examples:**
```
NEON.BET.D09.002825
NEON.BET.D15.001234
NEON.BET.D03.005678
```
