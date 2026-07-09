# Minesweeper Exploration RPG

Godot 4 prototype for a minesweeper-style exploration RPG.

## Run

Open this folder in Godot 4 and run `Main.tscn`.

## Controls

- Move: arrow keys or `WASD`
- Move by mouse: click an adjacent grid cell
- Restart: `R` or the side-panel restart button

## Implemented Rules

- 19 x 19 map, fixed start at `(9, 9)`, random edge treasure.
- Hidden route generation for basic reachability.
- 12 altars with early, mid, late, and treasure-near placement constraints.
- Around 112 enemies by default, scaled by Chebyshev distance from center.
- Extra low-level enemies are seeded around altars to create safer combat opportunities.
- Enemy rewards scale by level and are shown in the enemy key.
- Minesweeper numbers count enemies in the surrounding 8 cells.
- Vision values 4-8 reveal orthogonal cells plus diagonals in the specified order.
- Enemy reveal thresholds follow the script plan.
- Combat, reward points, defense loss, movement depletion, altar redistribution, and treasure victory.
