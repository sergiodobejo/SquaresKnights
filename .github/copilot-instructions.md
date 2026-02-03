# Copilot Instructions for RobloxRojoTest

## Project Overview
This is a Roblox game project using **Rojo**, a sync tool that enables editing Roblox games in an external code editor. The project uses **Luau** (Roblox's dialect of Lua) for all game logic.

## Architecture & File Structure

### Directory Layout
```
src/
  ├── client/     → Client-side scripts (StarterPlayer.StarterPlayerScripts)
  ├── server/     → Server-side scripts (ServerScriptService)
  └── shared/     → Shared modules available to both client and server (ReplicatedStorage)
```

### Rojo Project Mapping
- `default.project.json` defines how source files map to Roblox DataModel:
  - `src/shared/` → `ReplicatedStorage` (both client & server can access)
  - `src/server/` → `ServerScriptService` (server-only execution)
  - `src/client/` → `StarterPlayer.StarterPlayerScripts` (client-only execution)

### Key Files
- **`default.project.json`**: Defines project structure and how Rojo syncs files to Roblox DataModel. Modify when adding new service-level folders.
- **`aftman.toml`**: Manages toolchain. Currently pins Rojo v7.7.0-rc.1 (release candidate).
- **`src/shared/Hello.luau`**: Returns a function; exemplifies module pattern for shared code.

## Code Patterns & Conventions

### File Naming
- **Scripts** (direct execution): `*.client.luau`, `*.server.luau`
  - Example: `hello.client.luau`, `hello.server.luau`
- **Modules** (require/import): PascalCase without suffix
  - Example: `Hello.luau` in shared/ can be required by other scripts

### Module Exports
Shared modules use function returns:
```luau
-- Hello.luau
return function()
    print("Hello, world!")
end
```
Scripts consume them similarly (though Rojo/Luau module semantics differ slightly from standard Lua).

## Development Workflow

### Prerequisites
- Install Aftman: https://github.com/LPGhatguy/aftman
- Install Roblox Studio

### Key Commands
- **`aftman install`**: Installs tools defined in `aftman.toml` (run once in project root)
- **`rojo serve`**: Starts dev server syncing code changes to Roblox Studio in real-time
  - Connect in Studio: File → Rojo → Connect (localhost:34872 by default)
  - Changes to files in `src/` auto-sync to Studio
- **`rojo build`**: Creates `.rbxl` or `.rbxm` binary for standalone distribution

### Client-Server Communication
- **ReplicatedStorage** (`src/shared/`): Safe place for shared logic (both can read)
- **ServerScriptService** (`src/server/`): Server-only; use for game logic, database calls
- **StarterPlayer Scripts** (`src/client/`): Client-only; use for UI, input handling
- RemoteEvents/RemoteFunctions: Used for client↔server communication (define in shared, trigger in client/server)

#### Important: Remotes folder policy (Rojo)
- DO NOT add a `Remotes` folder under `src/` (or map it in `default.project.json`). Rojo syncing a `Remotes` folder can overwrite existing Remotes created/managed in Roblox Studio.
- Prefer creating/ensuring RemoteEvents at runtime on the server ("getOrCreate" into `ReplicatedStorage`) and consuming them from client/server code.
- If runtime creation is not feasible, instruct the user to create the required RemoteEvent manually in Studio, including the exact name and location.

## Development Guidelines

### When to Add/Modify Code
- Add **server-side logic** in `src/server/` (game rules, data validation, security)
- Add **client-side logic** in `src/client/` (UI, input, visuals)
- Add **shared utilities** in `src/shared/` (constants, helper functions, module definitions)

### Conventions to Follow
- Use Luau type annotations where possible for clarity
- Keep client and server responsibilities separate (security first)
- Shared modules should be stateless utilities, not service managers
- Name scripts and modules clearly so their purpose is obvious

## NPC Orientation & Pivot (Important)
Some NPC models have a pivot that is not aligned with `HumanoidRootPart` (HRP). If you rotate the whole model using `Model:PivotTo(CFrame.lookAt(...))`, the NPC can briefly "flip" / fall face-down or rotate unexpectedly.

Preferred approach when turning NPCs:
- Rotate based on `HumanoidRootPart` and apply a delta transform to the model.
- Compute the delta between current HRP and desired HRP, then apply it to `Model:GetPivot()`.

Useful Studio Command Bar snippets to inspect HRP axes:
- `local hrp = workspace:WaitForChild("LiveNPC"):FindFirstChildWhichIsA("Model"):FindFirstChild("HumanoidRootPart", true); print(hrp.CFrame.LookVector, hrp.CFrame.UpVector, hrp.CFrame.RightVector)`
- `print("Pivot", workspace:WaitForChild("LiveNPC"):FindFirstChildWhichIsA("Model"):GetPivot())`

## Integration Points & Dependencies
- **Roblox API**: All scripts access Roblox globals (game, script, workspace, Instance)
- **Aftman**: Manages Rojo version; upgrades require updating `aftman.toml`
- **Rojo v7.7.0-rc.1**: Active development; check release notes for breaking changes
- No external package manager (npm/pip) - Roblox modules only

## Common Tasks

### Add a New Shared Module
1. Create `src/shared/ModuleName.luau`
2. Export a function or table: `return { foo = function() ... end }`
3. Require in client/server: `local Module = require(game:GetService("ReplicatedStorage").ModuleName)`

### Add a Server Service
1. Create `src/server/ServiceName.server.luau`
2. Rojo auto-syncs to ServerScriptService
3. Use RemoteEvents for client communication (define in ReplicatedStorage)

### Add a Client Feature
1. Create `src/client/FeatureName.client.luau`
2. Rojo auto-syncs to StarterPlayer.StarterPlayerScripts
3. Access shared modules via ReplicatedStorage
