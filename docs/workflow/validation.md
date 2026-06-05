# Validation Logic and Quality Control

## Conservative Auto-Correction Protocol

The workflow implements strict requirements for automated metadata correction to prevent erroneous updates:

**Unanimous Agreement Requirement:**
All four redundant specimen queries (first, second, penultimate, last) must return identical values that differ from manual entry before auto-correction is applied.

**Implemented for:**
- Domain ID corrections (with cascading individual ID reformatting)
- Collection year validation
- Species identity updates (with preservation of specific IDs over generic placeholders)
- Taxonomic identification status

**Documentation:**
All corrections logged in `processingNotes` field with details of:
- Original manually entered value
- Corrected value from database
- Query results from all four specimens
- Timestamp and processing stage

## Spatial Order Validation

Sequential ordering of specimens within trays is critical for automated linkage:

**Assumptions:**
- Physical specimens arranged in ascending order by numeric portion of individual ID
- Spatial position in image corresponds to database sequence
- Out-of-order specimens trigger manual review

**Validation:**
- Expected specimen count compared to database query results
- Order position assigned based on spatial arrangement and sequential IDs
- Mismatches flagged for student verification

## Species Validation Logic

Conservative approach preserves information while correcting clear errors:

**Auto-Correction Criteria:**
- All four specimen queries return identical species name
- Returned name differs from manual entry
- Manual entry is generic placeholder ("Carabidae sp.") and database has specific identification
- Unanimous agreement across all queries

**Preservation:**
- Specific manual identifications retained over generic database entries
- Ambiguous cases (conflicting query results) flagged for manual review
- Recent identifications in manual entry preserved over outdated database records

## Duplicate Resolution Rationale

**Source Priority Logic:**
Hierarchy reflects data quality confidence:
1. Manual verification - Highest confidence, directly verified against physical specimens
2. ABTrays - Most recent, standardized protocol with trained students
3. SmallBeetles - Recent, specialized protocol for difficult specimens
4. CTrays - Recent, but complex multi-tray images
5. Belitz - Historical campaign, quality-filtered but older methods
6. FirstPass - Earliest campaign, variable quality

**Spatial Consistency:**
When same individual appears in same image at same position from multiple sources, most reliable source retained. When positions differ, manual verification prioritized as it involves physical specimen checking.

**Cross-Image Duplicates:**
Individual IDs appearing in multiple different images retained with quality flags rather than automatic resolution, as these may represent:
- Legitimate re-imaging for quality improvement
- Specimen curation errors (mislabeled specimens)
- Transcription errors in one or both records
- Database linkage errors requiring expert review
