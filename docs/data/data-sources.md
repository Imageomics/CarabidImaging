# Data Source Descriptions

## ABTrays
Standard A and B format specimen trays imaged by trained student researchers at the NEON Biorepository. Images follow standardized protocols with species labels, collection metadata, color reference cards, and 0-1 cm scale bars. Specimens arranged in sequential order by NEON individual ID.

**Characteristics:**
- High image quality
- Complete metadata from imaging session
- Direct processing workflow
- Represents majority of specimens

## CTrays
C format trays containing multiple sub-trays per image. Each image may contain specimens from multiple trays requiring tray-level tracking.

**Characteristics:**
- Multiple trays per image
- Tray ID field for specimen-to-tray mapping
- Specialized handling in data integration
- Distinct final image naming convention

### FirstPass
Initial imaging campaign conducted by NEON with variable image quality and incomplete metadata. Requires quality filtering before processing.

**Characteristics:**
- Variable image resolution and focus
- Missing metadata requiring transcription
- Two-stage processing with quality filtering
- Historical dataset from early digitization efforts

## Belitz
Images from Michael Belitz's ground beetle imaging campaign. Some images have focus issues requiring quality assessment.

**Characteristics:**
- Variable image quality
- Quality annotation and filtering required
- Extended workflow matching FirstPass
- Independent imaging methodology

## SmallBeetles
Processing the images of the small beetles imaged by Aly East at the NEON Biorepository. These data are distinct from other data streams to account for the beetle size. Specialized imaging protocol for small-bodied beetle specimens requiring magnification. Modified imaging setup lacks standardized header information.

**Characteristics:**
- High magnification for small specimens
- Modified imaging protocol
- No standardized header labels
- Specialized handling for image IDs
