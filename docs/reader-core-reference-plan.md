# Reader Core Reference Plan

## Goal

Rebuild the reader core around patterns that are already proven in stable reader
projects, instead of continuing with ad-hoc state fixes.

This document is the implementation baseline for the next reader refactor.

## Reference Repositories

### 1. Koodo Reader

Repository:
- https://github.com/koodo-reader/koodo-reader

Files inspected:
- `src/models/BookLocation.ts`
- `src/pages/reader/component.tsx`

Useful concepts:
- Reading position is stored as a dedicated model, not as loose UI state.
- Stored location includes multiple views of the same position:
  - chapter metadata
  - percentage
  - CFI / stable locator
  - page label
- Reader UI delegates actual navigation to a viewer/rendition object.

Takeaway for Koofy:
- We need a first-class locator model for "where the user is".
- Single/double mode must not own the canonical reading position.

### 2. foliate-js

Repository:
- https://github.com/johnfactotum/foliate-js

Files inspected:
- `paginator.js`
- `progress.js`
- `search.js`
- `reader.js`

Useful concepts:
- Pagination is a standalone engine, not embedded in the page widget.
- Progress is modeled as section/fraction/location transforms.
- Search is a standalone matcher over normalized text segments.
- UI flow mode (`paginated` vs `scrolled`) is a renderer attribute, while
  progress remains mode-independent.
- Reader UI listens to relocation events instead of recomputing everything
  from scratch on each tap.

Takeaway for Koofy:
- Progress must be mode-independent.
- Pagination must be a service/session layer.
- Search/indexing must live outside `ReaderPage`.

### 3. Flutter-specific direction

The originally requested `harsh7786/epub_viewer` GitHub repository was not
available to clone directly during this session.

Practical takeaway:
- Flutter should be treated as the shell and state wiring layer.
- The reader engine concepts should come from stable reader implementations,
  not from a Flutter widget-first design.

## Current Koofy Problems

### A. Canonical position is still ambiguous

Current code stores and mixes:
- `contentOffset`
- `positionRatio`
- `scrollOffsetPx`
- `scrollMaxExtentPx`
- `anchor`
- spread index derived from current pages

Result:
- Single mode and double mode can each become the accidental source of truth.
- Mode changes can restore from different sources depending on timing.

### B. `ReaderPage` still owns too much orchestration

`lib/features/reader/presentation/reader_page.dart` still coordinates:
- current mode
- pending anchors
- spread jump state
- scroll restore state
- pagination requests
- relocation
- progress save timing

Result:
- correct behavior depends on subtle ordering of frame callbacks and flags.

### C. Pagination and progress are not modeled as one system

Current code already has good pieces:
- `ReaderTextDocument`
- `ReaderProgressService`
- `ReaderProjectionService`
- `ReaderSpreadPaginationService`

But they are still wired from `ReaderPage` with widget-driven timing.

### D. Search/indexing still leaks presentation concerns

The content indexer and search logic are usable, but the reader page still
decides too much about when and how search jumps are interpreted.

## Target Architecture

## 1. ReaderLocator

Add one canonical locator model for saved reading position.

Requirements:
- mode-independent
- stable across single/double/scrolled layouts
- serializable
- derived from indexed text structure, not scroll pixels

Recommended shape:
- `chapterId`
- `paragraphIndex`
- `charOffset`
- `globalOffset`
- `progressFraction`

Notes:
- `globalOffset` is useful for fast jumps.
- `progressFraction` is useful as a fallback only.
- scroll pixels should not be canonical persisted state.

## 2. ReaderDocument

Keep and expand `ReaderTextDocument` as the source document model.

It should own:
- raw normalized content
- paragraph ranges
- chapter ranges
- anchor/locator conversions
- search source text

It should not know:
- widget scroll position
- view mode

## 3. ReaderPaginationSession

Create a session object for layout-specific pagination.

Responsibilities:
- accept document + viewport + style + mode
- produce page/spread map
- map locator to page/spread index
- map visible page/spread back to locator
- cache by layout signature

Modes:
- single-scroll
- single-paginated
- double-paginated

Important:
- each mode derives from the same locator
- mode switching must mean "reproject the same locator", not "save one mode and
  guess in the other"

## 4. ReaderProgressCoordinator

Move relocation and persistence decisions out of `ReaderPage`.

Responsibilities:
- decide the current canonical locator
- handle mode transitions
- queue restores
- debounce persistence
- expose one read-only state object to the widget

This is the layer that should replace most pending flags in `ReaderPage`.

## 5. ReaderSearchIndex

Search should be document-level, not page-level.

Responsibilities:
- tokenize or normalize source text
- return locator-aware results
- build excerpts
- allow jump-to-result through locator projection

This follows the `foliate-js/search.js` direction more closely than our current
page-driven jump flow.

## Keep / Replace / Retire

### Keep

- `ReaderTextDocument`
- `ReaderProgressService`
- `ReaderProjectionService`
- `ReaderSpreadPaginationService`
- `ReaderContentIndexer`
- `ReadingAnchor` as a building block

### Replace

- `ReadingProgress` persistence shape
  - keep backward compatibility when reading old data
  - persist new canonical locator model
- mode transition logic in `ReaderPage`
- jump/restore orchestration in `ReaderPage`

### Retire or shrink heavily

- widget-owned pending transition flags as the primary control system
- pixel-based persisted restore as a main path
- pagination decisions that depend on transient widget timing

## Implementation Phases

### Phase 1. Freeze the core contract

Tasks:
- add `ReaderLocator`
- redefine saved progress around locator-first persistence
- add a compatibility loader for old progress data

### Phase 2. Move projection into coordinator/session

Tasks:
- introduce `ReaderPaginationSession`
- introduce `ReaderProgressCoordinator`
- make `ReaderPage` consume coordinator state instead of owning restore logic

### Phase 3. Unify mode switching

Tasks:
- single -> double projects the same locator into the double session
- double -> single projects the same locator into the single session
- library reopen always restores via locator, never via last widget pixels

### Phase 4. Search and indexing cleanup

Tasks:
- expose document-level search results as locators
- jump to search result through coordinator projection

## Immediate Patch Targets

These are the first files to rewrite around the new plan:

- `lib/features/reader/domain/reading_progress.dart`
- `lib/features/reader/presentation/reader_page.dart`
- `lib/features/reader/presentation/controllers/reader_session_controller.dart`

## Current Breakages To Eliminate

These are the symptoms that confirm we still have widget-timed orchestration
instead of a reader-core contract:

- search dialog / IME can temporarily flip single mode into double mode
- search jumps can execute before viewport stabilization completes
- double-mode search can reopen on the same locator but a different visual
  spread placement
- double-mode tap navigation can stall on a thin tail window and then refill on
  the next interaction
- mode changes can briefly render the previous mode before relocation catches up

These breakages all point to the same missing boundary:
- canonical relocation target
- view projection session
- widget lifecycle timing

## First Refactor Slice

The safest first extraction is search.

Reason:
- search currently returns raw offsets
- raw offsets are immediately interpreted by widget-local jump logic
- search therefore inherits all current mode/viewport timing problems

The first refactor slice should produce:

1. `ReaderSearchResult`
- query
- excerpt
- global offset
- anchor
- locator

2. `ReaderSearchService`
- consumes `ReaderTextDocument`
- returns locator-aware results
- owns normalization and excerpt building

3. `ReaderPage` integration later
- convert UI search selection into a canonical relocation target
- let the pagination/session layer project that target into single/double

This gives us a concrete migration path:
- search stops depending on transient widget state first
- relocation can then be unified around locator projection
- new coordinator layer under:
  - `lib/features/reader/core/coordinator/`
  - or `lib/features/reader/core/session/`

## Non-goals

Not a priority for this refactor:
- visual redesign
- UX polish
- ad behavior changes
- extra reader settings

The priority is engine stability:
- location restore
- single/double consistency
- pagination correctness
- search/indexing correctness
