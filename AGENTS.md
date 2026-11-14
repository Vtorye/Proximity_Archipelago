## 1. Scope and normative language

This document defines mandatory architectural requirements for all code and game content created or modified in this project.

Target environment:
- Engine: Godot 4.7.2 stable.
- Language: GDScript 2.0.
- Documentation: Godot 4.7.

The following normative terms are used throughout this document:

- **MUST** — an absolute requirement. The implementation must comply.
- **MUST NOT** — an absolute prohibition. The implementation must not violate it.
- **MAY** — an explicitly permitted approach that can be used when appropriate.

An agent MUST NOT silently disregard a MUST or MUST NOT requirement.

If a requirement cannot be satisfied due to a concrete technical limitation, the agent MUST explain the limitation, describe the alternatives and request approval before making an architectural exception.

## 2. Fundamental architectural principles

The project MUST follow native Godot architectural conventions.

Godot Editor is a primary development environment, not merely a runtime launcher.

Game content MUST remain understandable, inspectable and editable through standard Godot Editor functionality.

Correct runtime behavior alone MUST NOT be considered sufficient evidence of a correct implementation.

The architecture MUST distinguish between:

- Scene structure and composition.
- Configuration and authored game data.
- Runtime state.
- Application and gameplay logic.
- Editor-authored content and procedurally generated content.

The implementation MUST use the simplest architecture that satisfies the actual requirements.

## 3. Scene structure and node construction

### 3.1. Authored scene structure

If a node hierarchy is static and/or known before runtime, that hierarchy MUST be represented in a `.tscn` scene.

If a hierarchy is part of authored game content and is intended to be inspected or modified through Godot Editor, it MUST be stored as a scene rather than constructed procedurally.

Predetermined node hierarchies MUST NOT be constructed in `_init()`, `_enter_tree()`, `_ready()` or helper methods.

A scene MUST NOT be reduced to a single root node whose script constructs the entire predetermined hierarchy.

Reusable game entities MUST be implemented as independent scenes and instantiated using `PackedScene.instantiate()`.

### 3.2. Dynamic structures

Node hierarchies MAY be constructed programmatically when their composition genuinely depends on runtime data, algorithms or unpredictable conditions.

For example:
- Procedurally generated maps.
- Dynamically populated inventories.
- Runtime-generated enemy formations.
- Data-dependent collections of objects.

Even when the overall structure is dynamic, reusable entities MUST use existing scene templates whenever applicable.

Dynamic construction MUST NOT be used as a substitute for editor-authored structures.

### 3.3. Scene composition

Scenes MUST have meaningful and understandable node hierarchies.

Child scenes MUST be used for reusable structural components.

Scene inheritance MAY be used for meaningful variations of existing scenes.

Composition MUST be preferred over unnecessarily deep inheritance hierarchies.

### 3.4. Scene Tree semantics

Parent-child relationships MUST represent meaningful structural, spatial, logical or lifecycle relationships.

Nodes MUST NOT be placed in a hierarchy solely for convenient access or arbitrary grouping when that hierarchy misrepresents their actual relationships.

The lifetime of child nodes MUST be consistent with their intended ownership.

## 4. Configuration and parameter management

### 4.1. Externally editable parameters

If a system changes its behavior depending on configurable parameters, those parameters MUST have an editing interface outside the source code.

Parameters intended for gameplay balancing, designer configuration or content customization MUST NOT be hardcoded.

Appropriate editing interfaces MAY include:
- Exported GDScript properties.
- Custom Godot Resources.
- Inspector properties.
- Godot Editor tools.
- Other native editor-accessible mechanisms.

Where appropriate, exported properties MUST use meaningful types, ranges, descriptions, categories and groups.

### 4.2. Constants and hardcoded values

Every constant MUST have a clear technical justification.

Constants MAY represent:
- Mathematical or algorithmic invariants.
- Fixed engine or protocol values.
- Structural limits that are genuinely immutable.
- Internal implementation details.
- Values that are not intended to be configured or balanced.

Constants MUST NOT be used to hide parameters that should be configurable.

Magic numbers and unexplained hardcoded values MUST NOT be introduced.

A value MUST NOT be declared constant merely because it is convenient to do so.

### 4.3. Resource-based configuration

When a system can have multiple instances with independently configurable parameters, those parameters MAY be represented by a dedicated custom Resource.

A custom Resource MUST provide a clear, typed contract for the parameters consumed by the system.

For example:

- `Building.tscn` — building structure.
- `Building.gd` — building behavior.
- `BuildingDefinition.gd` — Resource class defining building parameters.
- `BuildingDefinition.tres` — actual building configuration.

Resources MUST NOT be introduced unnecessarily when exported properties are sufficient.

## 5. Configuration and runtime state separation

Configuration data and mutable runtime state MUST be separated when they have different purposes or lifecycles.

For example:

Configuration:
- Maximum health.
- Construction cost.
- Movement speed.
- Attack range.
- Production rate.

Runtime state:
- Current health.
- Current construction progress.
- Current target.
- Current production state.

A shared configuration Resource MUST NOT accidentally become shared mutable runtime state.

If an instance requires independently mutable resource data, the implementation MUST explicitly ensure that the instance receives independent data, for example through resource duplication or appropriate local-to-scene resource behavior.

Runtime modifications MUST NOT unintentionally affect other instances using the same configuration.

## 6. Native Godot functionality

If Godot provides functionality that satisfies the requirements of a system, that functionality MUST be used instead of an independent implementation.

Examples include, but are not limited to:

- Nodes and built-in physics bodies.
- Signals and groups.
- PackedScenes and Resources.
- AnimationPlayer and Tween.
- InputMap.
- Built-in navigation systems.
- Built-in UI containers and controls.
- Theme and StyleBox resources.
- TileMapLayer and other native level-building tools.

Custom implementations MAY be introduced when native functionality does not satisfy the actual requirements.

An agent introducing custom functionality in place of an existing engine feature MUST provide a concrete technical justification.

Duplicating native functionality without a demonstrated need MUST NOT be done.

## 7. Encapsulation and component boundaries

Reusable scenes and systems MUST have clearly defined responsibilities.

A reusable scene MUST expose an understandable interface for interaction with its external environment.

Such interfaces MAY include:
- Public methods.
- Signals.
- Exported properties.
- Resource references.
- Explicitly assigned node references.

A scene MUST NOT rely on undocumented assumptions about the structure of its parent or ancestor scenes.

Absolute NodePaths and arbitrary references to unrelated parts of the SceneTree MUST NOT be used as substitutes for explicit dependencies.

External systems MUST interact with a scene through its intended interface rather than relying on knowledge of its internal node hierarchy.

Dependencies MUST be explicit and understandable.

## 8. Communication between systems

Signals MUST be used for event notification and communication between systems that should remain loosely coupled.

Direct method calls MUST be used when there is an explicit dependency and direct interaction is appropriate.

Global event dispatchers MUST NOT be introduced as a default communication mechanism.

Signals, groups and Autoloads MUST NOT be used indiscriminately when a simpler native mechanism is sufficient.

## 9. Global systems and Autoloads

Autoloads MAY be used for genuinely global services whose lifecycle and accessibility justify global scope.

Autoloads MUST NOT be used merely to avoid passing dependencies or maintaining appropriate scene relationships.

Individual game entities MUST NOT become global services without a clear architectural reason.

A central manager MUST NOT become a universal owner of unrelated game functionality.

## 10. Data and content architecture

Designer-adjustable game content MUST be represented in editor-accessible forms.

Item definitions, building definitions, character configurations, balance parameters and similar data SHOULD be represented using appropriate Godot Resources.

Runtime entities MUST NOT unnecessarily contain their own duplicated hardcoded definitions.

When multiple entities share a common data schema, that schema MUST have a clearly defined representation.

Data structures MUST use appropriate types and MUST NOT rely unnecessarily on loosely structured dictionaries or arbitrary string identifiers when typed Resources or other native structures provide a better solution.

## 11. Abstraction and complexity

The implementation MUST use the simplest architecture that satisfies the requirements.

Universal factories, generic managers, wrappers, registries, service locators and additional infrastructure MUST NOT be introduced without a demonstrated need.

A custom abstraction MAY be introduced when it addresses a concrete problem involving reuse, coupling, maintainability or complexity.

Abstractions MUST have clearly defined responsibilities.

An abstraction MUST NOT merely wrap an existing Godot mechanism without providing meaningful additional functionality.

Premature generalization MUST NOT take precedence over a clear, understandable implementation.

## 12. Editor accessibility and designer workflow

The project MUST remain editable through Godot Editor without requiring game designers to understand or modify GDScript.

Designer-adjustable content MUST be exposed through appropriate editor interfaces.

This includes, where applicable:
- Scene hierarchy and composition.
- Transforms and layout.
- Collision shapes.
- Visual and audio resources.
- Gameplay parameters.
- Item and building configurations.
- Animation resources.
- Spawn points and placement.
- Level composition.

Content intended for visual editing MUST NOT be hidden inside procedural code or opaque data structures.

If a feature requires specialized editor functionality, an appropriate editor tool or plugin MAY be implemented.

## 13. Procedural generation

Procedural generation MAY be used when content is genuinely derived from algorithms, runtime data or generated conditions.

Generated objects MUST use reusable scene templates when applicable.

Generated entities MUST use appropriate configuration resources when they share a common data schema.

Procedural generation MUST NOT replace static authored content without a concrete reason.

Generated content MUST remain inspectable and debuggable where practical.

## 14. Implementation workflow

Before implementing a feature, the agent MUST:

1. Inspect the existing project architecture.
2. Identify relevant scenes, resources, scripts and dependencies.
3. Determine which structures are authored and which are genuinely dynamic.
4. Identify existing engine functionality that satisfies the requirements.
5. Reuse existing project conventions and components where appropriate.
6. Select the simplest architecture that satisfies the requirements.

The agent MUST NOT rewrite unrelated systems or introduce architectural changes outside the scope of the task without justification.

Existing project architecture MUST be respected unless there is a concrete reason to change it.

## 15. Validation and definition of done

An implementation MUST NOT be considered complete merely because it works at runtime.

Before completing a task, the agent MUST verify that:

- The implementation follows this document.
- Static scene structures are represented in scene files.
- Configurable parameters are accessible outside the source code.
- Configuration and runtime state are appropriately separated.
- Native Godot functionality is used where applicable.
- Scene and system boundaries are understandable.
- Dependencies are explicit.
- Resources and scene references are valid.
- Changes do not unnecessarily complicate existing architecture.

The agent MUST report any architectural exceptions, technical limitations or unresolved validation issues.

A feature is architecturally complete only when it is functional, maintainable and compatible with the project's intended Godot Editor workflow.
