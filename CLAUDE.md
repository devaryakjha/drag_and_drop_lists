# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**drag_and_drop_lists** is a Flutter package that provides two-level drag-and-drop reorderable lists. It allows users to reorder items within lists, reorder entire lists, and drag new items between lists. The package supports multiple layout modes (vertical/horizontal), expandable lists, and can be used with slivers.

## Architecture

### Core Widget Structure

The package uses a **nested widget hierarchy** to manage drag-and-drop interactions across two levels (lists and items):

- **DragAndDropLists** (`drag_and_drop_lists.dart`): The main widget that manages the outer list of `DragAndDropListInterface` objects. Handles:
  - Pointer tracking for drag detection and auto-scrolling
  - Reordering of lists and items via callbacks
  - Layout modes (vertical/horizontal, sliver/regular ListView)
  - Ghost widgets for visual feedback during dragging

- **DragAndDropListInterface** (`drag_and_drop_list_interface.dart`): Abstract interface for list implementations:
  - `DragAndDropList`: Standard list container
  - `DragAndDropListExpansion`: Collapsible list using `ProgrammaticExpansionTile` (requires `listGhost` to be set)

- **DragAndDropItem** (`drag_and_drop_item.dart`): Individual items within lists that can be reordered

### Supporting Components

- **Wrapper Classes**: `DragAndDropListWrapper` and `DragAndDropItemWrapper` wrap the core components and handle drag-drop detection
- **Target Classes**: `DragAndDropListTarget` and `DragAndDropItemTarget` represent drop zones
- **Parameters**: `DragAndDropBuilderParameters` passes configuration through the widget tree
- **Utilities**:
  - `MeasureSize`: Measures widget dimensions for proper ghost sizing
  - `DragHandle`: iOS-style drag handles alternative to long/short press
  - `ProgrammaticExpansionTile`: Custom expansion tile with programmatic control

### Key Design Patterns

1. **Callback-based Reordering**: The parent widget is responsible for updating its data model. Callbacks provide:
   - `onItemReorder`: Item moved within/between lists
   - `onListReorder`: List reordered
   - `onItemAdd`/`onListAdd`: New items/lists added from external sources
   - Acceptance callbacks (`onWillAccept`) for custom drop rules

2. **Two-level Target System**: Each level has potential drop targets:
   - Items between items in a list
   - Items at the end of a list
   - Lists between lists
   - Lists at the end of all lists

3. **Pointer Tracking**: The `DragAndDropListsState` tracks pointer position to:
   - Enable auto-scrolling when dragging near edges
   - Calculate drag positions for smooth interactions
   - Support both vertical and horizontal scroll axes

## Development Commands

### Building and Analyzing

```bash
# Get dependencies for the main package
flutter pub get

# Get dependencies for the example app
cd example && flutter pub get && cd ..

# Analyze code for errors and lints
flutter analyze

# Format code
dart format lib/
dart format example/lib/
dart format test/
```

### Running Tests

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/drag_and_drop_lists_test.dart

# Run tests with coverage
flutter test --coverage
```

### Running the Example

```bash
# Run the example app on the default device
cd example && flutter run && cd ..

# Run on a specific device (list devices with: flutter devices)
cd example && flutter run -d <device_id> && cd ..
```

### Linting

The project uses Flutter lints defined in `analysis_options.yaml`. The linter inherits from `package:flutter_lints/flutter.yaml`. Run `flutter analyze` to check for lints.

## FVM Configuration

The project uses FVM (Flutter Version Manager) with the stable channel. The configuration is in `.fvmrc`. VS Code is configured to use the FVM SDK path (`.fvm/versions/stable`).

## Important Notes

- **DragAndDropListExpansion Requirement**: If your lists use `DragAndDropListExpansion` or any class inheriting from `DragAndDropListExpansionInterface`, you **must** provide a non-null `listGhost` widget to `DragAndDropLists`. This is enforced via an assertion in the constructor.

- **Sliver Lists**: When using `sliverList: true`, a `scrollController` is required. The `DragAndDropLists` widget supports both regular ListView and sliver-compatible output.

- **Horizontal Lists**: When setting `axis` to `Axis.horizontal`, you must provide a finite value for `listWidth`. Horizontal + sliver mode is not currently supported.

- **Auto-scrolling**: The widget automatically scrolls lists when dragging near the edges. Scrolling can be disabled by setting `disableScrolling: true`.

## Common Extension Points

- **Custom List Layouts**: Create new classes inheriting from `DragAndDropListInterface` with different `generateWidget()` implementations
- **Drag Handles**: Provide a `DragHandle` instance to `listDragHandle` or `itemDragHandle` for custom drag affordances
- **Acceptance Rules**: Use `listOnWillAccept` and `itemOnWillAccept` callbacks to implement custom drop rules (e.g., prevent items from being added to certain lists)
- **Visual Customization**: Use `itemGhost`, `listGhost`, `itemDecorationWhileDragging`, `listDecorationWhileDragging`, and divider widgets to customize appearance
