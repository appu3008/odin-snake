package snake

import rl "vendor:raylib"
import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:time"

// Grid / window layout --------------------------------------------------------
GRID_W :: 24
GRID_H :: 18
CELL   :: 32
WINDOW_W :: GRID_W * CELL // 768
WINDOW_H :: GRID_H * CELL // 576

START_TICK :: 0.14       // seconds per move at the start
MIN_TICK   :: 0.055      // fastest the snake ever gets
SPEED_UP   :: 0.0035     // seconds shaved off per food eaten

// Colors ----------------------------------------------------------------------
BG        :: rl.Color{ 26, 28, 32, 255 }
BG_CHECK  :: rl.Color{ 31, 34, 39, 255 }
SNAKE_BODY_1 :: rl.Color{ 56, 158, 74, 255 }
SNAKE_BODY_2 :: rl.Color{ 46, 132, 61, 255 }
SNAKE_HEAD   :: rl.Color{ 120, 220, 130, 255 }
FOOD_COLOR   :: rl.Color{ 230, 72, 72, 255 }
FOOD_OUTLINE :: rl.Color{ 160, 40, 40, 255 }
TEXT_DIM     :: rl.Color{ 150, 155, 165, 255 }
OVERLAY      :: rl.Color{ 0, 0, 0, 160 }

// Types -----------------------------------------------------------------------
Cell :: struct {
	x, y: i32,
}

Dir :: enum {
	Up,
	Down,
	Left,
	Right,
}

State :: enum {
	Playing,
	GameOver,
}

Game :: struct {
	snake:    [GRID_W * GRID_H]Cell, // index 0 is the head
	len:      int,
	dir:      Dir,
	next_dir: Dir, // turn buffered for the next tick
	food:     Cell,
	score:    int,
	best:     int,
	state:    State,
	won:      bool,
	acc:      f32,
	tick:     f32,
}

DIR_VEC := [Dir]Cell{
	.Up    = { 0, -1 },
	.Down  = { 0, 1 },
	.Left  = { -1, 0 },
	.Right = { 1, 0 },
}

opposite :: proc(d: Dir) -> Dir {
	switch d {
	case .Up:    return .Down
	case .Down:  return .Up
	case .Left:  return .Right
	case .Right: return .Left
	}
	return d
}

// Game logic ------------------------------------------------------------------
reset_game :: proc(g: ^Game) {
	cx, cy := i32(GRID_W / 2), i32(GRID_H / 2)
	g.len = 3
	for i in 0 ..< g.len {
		g.snake[i] = Cell{ cx - i32(i), cy }
	}
	g.dir      = .Right
	g.next_dir = .Right
	g.score    = 0
	g.state    = .Playing
	g.won      = false
	g.acc      = 0
	g.tick     = START_TICK
	spawn_food(g)
}

spawn_food :: proc(g: ^Game) {
	if g.len >= len(g.snake) {
		g.won   = true
		g.state = .GameOver
		if g.score > g.best {
			g.best = g.score
		}
		return
	}
	for {
		c := Cell{
			i32(rand.int_range(0, GRID_W)),
			i32(rand.int_range(0, GRID_H)),
		}
		clear := true
		for i in 0 ..< g.len {
			if g.snake[i] == c {
				clear = false
				break
			}
		}
		if clear {
			g.food = c
			return
		}
	}
}

try_turn :: proc(g: ^Game, d: Dir) {
	// Ignore input while a turn is already buffered, and never reverse into
	// the snake's own neck or repeat the current direction.
	if g.next_dir != g.dir {
		return
	}
	if d == g.dir || d == opposite(g.dir) {
		return
	}
	g.next_dir = d
}

handle_input :: proc(g: ^Game) {
	if rl.IsKeyPressed(rl.KeyboardKey.UP) || rl.IsKeyPressed(rl.KeyboardKey.W) {
		try_turn(g, .Up)
	}
	if rl.IsKeyPressed(rl.KeyboardKey.DOWN) || rl.IsKeyPressed(rl.KeyboardKey.S) {
		try_turn(g, .Down)
	}
	if rl.IsKeyPressed(rl.KeyboardKey.LEFT) || rl.IsKeyPressed(rl.KeyboardKey.A) {
		try_turn(g, .Left)
	}
	if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) || rl.IsKeyPressed(rl.KeyboardKey.D) {
		try_turn(g, .Right)
	}
	if g.state == .GameOver {
		if rl.IsKeyPressed(rl.KeyboardKey.R) || rl.IsKeyPressed(rl.KeyboardKey.ENTER) || rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			reset_game(g)
		}
	}
}

// Advance the simulation by one cell.
step :: proc(g: ^Game) {
	g.dir = g.next_dir
	v := DIR_VEC[g.dir]

	nh := Cell{
		g.snake[0].x + v.x,
		g.snake[0].y + v.y,
	}

	// Wall collision.
	if nh.x < 0 || nh.y < 0 || nh.x >= GRID_W || nh.y >= GRID_H {
		g.state = .GameOver
		if g.score > g.best {
			g.best = g.score
		}
		return
	}

	will_eat := nh == g.food

	// Self collision. The tail tip is allowed to move into the head's old
	// cell unless the snake is about to grow.
	limit := g.len
	if !will_eat {
		limit -= 1
	}
	for i in 0 ..< limit {
		if g.snake[i] == nh {
			g.state = .GameOver
			if g.score > g.best {
				g.best = g.score
			}
			return
		}
	}

	// Shift the body toward the tail, then put the new head at index 0.
	new_len := g.len
	if will_eat {
		new_len += 1 // tail stays put, snake grows
	}
	for i := new_len - 1; i > 0; i -= 1 {
		g.snake[i] = g.snake[i - 1]
	}
	g.snake[0] = nh
	g.len = new_len

	if will_eat {
		g.score += 1
		g.tick = max(MIN_TICK, START_TICK - f32(g.score) * SPEED_UP)
		spawn_food(g)
	}
}

update :: proc(g: ^Game) {
	handle_input(g)
	if g.state != .Playing {
		return
	}
	g.acc += rl.GetFrameTime()
	for g.acc >= g.tick {
		g.acc -= g.tick
		step(g)
		if g.state != .Playing {
			g.acc = 0
			break
		}
	}
}

// Rendering -------------------------------------------------------------------
cell_rect :: proc(c: Cell, inset: f32) -> rl.Rectangle {
	return rl.Rectangle{
		f32(c.x) * CELL + inset,
		f32(c.y) * CELL + inset,
		CELL - inset * 2,
		CELL - inset * 2,
	}
}

draw_board :: proc() {
	for y in 0 ..< GRID_H {
		for x in 0 ..< GRID_W {
			if (x + y) % 2 == 0 {
				rl.DrawRectangle(i32(x * CELL), i32(y * CELL), CELL, CELL, BG_CHECK)
			}
		}
	}
}

draw_snake :: proc(g: ^Game) {
	// Body (tail first so the head is drawn on top).
	for i := g.len - 1; i >= 1; i -= 1 {
		color := SNAKE_BODY_1
		if i % 2 == 0 {
			color = SNAKE_BODY_2
		}
		rl.DrawRectangleRounded(cell_rect(g.snake[i], 3), 0.4, 8, color)
	}
	// Head.
	head := g.snake[0]
	rl.DrawRectangleRounded(cell_rect(head, 2), 0.4, 8, SNAKE_HEAD)

	// Eyes, offset toward the direction of travel.
	v := DIR_VEC[g.dir]
	cx := f32(head.x) * CELL + CELL / 2
	cy := f32(head.y) * CELL + CELL / 2
	perp := Cell{ -v.y, v.x } // perpendicular direction
	eye_sides := [2]f32{ -1, 1 }
	for s in eye_sides {
		rl.DrawCircleV(
			rl.Vector2{
				cx + f32(v.x) * 6 + f32(perp.x) * s * 5,
				cy + f32(v.y) * 6 + f32(perp.y) * s * 5,
			},
			2.5,
			BG,
		)
	}
}

draw_food :: proc(g: ^Game) {
	c := rl.Vector2{
		f32(g.food.x) * CELL + CELL / 2,
		f32(g.food.y) * CELL + CELL / 2,
	}
	rl.DrawCircleV(c, CELL / 2 - 5, FOOD_OUTLINE)
	rl.DrawCircleV(c, CELL / 2 - 8, FOOD_COLOR)
}

// String constants (untyped, so they convert to cstring implicitly).
TITLE_GAME_OVER :: "GAME OVER"
TITLE_WIN       :: "YOU WIN!"
PROMPT_RESTART  :: "Press R or Enter to play again"

draw_hud :: proc(g: ^Game) {
	score_text := rl.TextFormat("Score: %d", g.score)
	rl.DrawText(score_text, 12, 8, 22, rl.WHITE)

	best_text := rl.TextFormat("Best: %d", g.best)
	best_w := rl.MeasureText(best_text, 22)
	rl.DrawText(best_text, c.int(WINDOW_W) - best_w - 12, 8, 22, TEXT_DIM)
}

draw_game_over :: proc(g: ^Game) {
	rl.DrawRectangle(0, 0, WINDOW_W, WINDOW_H, OVERLAY)

	title: cstring = TITLE_GAME_OVER
	if g.won {
		title = TITLE_WIN
	}
	title_w := rl.MeasureText(title, 64)
	rl.DrawText(title, (c.int(WINDOW_W) - title_w) / 2, WINDOW_H / 2 - 70, 64, rl.WHITE)

	sub := rl.TextFormat("Score: %d   Best: %d", g.score, g.best)
	sub_w := rl.MeasureText(sub, 26)
	rl.DrawText(sub, (c.int(WINDOW_W) - sub_w) / 2, WINDOW_H / 2 + 10, 26, TEXT_DIM)

	prompt_w := rl.MeasureText(PROMPT_RESTART, 20)
	rl.DrawText(PROMPT_RESTART, (c.int(WINDOW_W) - prompt_w) / 2, WINDOW_H / 2 + 60, 20, rl.WHITE)
}

draw :: proc(g: ^Game) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(BG)
	draw_board()
	draw_food(g)
	draw_snake(g)
	draw_hud(g)

	if g.state == .GameOver {
		draw_game_over(g)
	}
}

// Entry point -----------------------------------------------------------------
expect :: proc(fails: ^int, cond: bool, msg: string) {
	if !cond {
		fmt.printf("  FAIL: %s\n", msg)
		fails^ += 1
	}
}

// Headless checks of the pure game logic (no window needed).
selftest :: proc() {
	fails := 0
	g: Game

	// 1. Reset state.
	reset_game(&g)
	expect(&fails, g.len == 3, "reset: snake length is 3")
	expect(&fails, g.dir == .Right, "reset: moves right")
	expect(&fails, g.state == .Playing, "reset: playing")

	// 2. Reversing into the neck is ignored.
	try_turn(&g, .Left)
	expect(&fails, g.next_dir == .Right, "no 180 degree turn")

	// 3. A legal turn is buffered for the next tick.
	try_turn(&g, .Up)
	expect(&fails, g.next_dir == .Up, "legal turn is buffered")

	// 4. A tick moves the head one cell in the buffered direction.
	step(&g)
	expect(&fails, g.snake[0] == Cell{12, 8}, "head moved up one cell")
	expect(&fails, g.len == 3, "length unchanged without food")

	// 5. Eating: score, growth, tail stays.
	reset_game(&g)
	g.food = Cell{13, 9} // directly right of the head
	step(&g)
	expect(&fails, g.score == 1, "score after eating")
	expect(&fails, g.len == 4, "snake grew after eating")
	expect(&fails, g.snake[0] == Cell{13, 9}, "head sits on the food cell")

	// 6. Food never spawns on the snake.
	reset_game(&g)
	food_ok := true
	for i := 0; i < 200; i += 1 {
		spawn_food(&g)
		for j in 0 ..< g.len {
			if g.food == g.snake[j] {
				food_ok = false
			}
		}
	}
	expect(&fails, food_ok, "food never spawns on the snake")

	// 7. Moving into the neck kills the snake.
	reset_game(&g)
	g.snake[0] = Cell{5, 5}
	g.snake[1] = Cell{5, 6}
	g.snake[2] = Cell{6, 6}
	g.snake[3] = Cell{6, 5}
	g.len    = 4
	g.dir    = .Down // next head (5,6) is the neck
	g.next_dir = .Down
	step(&g)
	expect(&fails, g.state == .GameOver, "self collision ends the game")

	// 8. Moving into the cell the tail is vacating is legal.
	reset_game(&g)
	g.snake[0] = Cell{5, 5}
	g.snake[1] = Cell{6, 5}
	g.snake[2] = Cell{6, 6}
	g.snake[3] = Cell{5, 6}
	g.len      = 4
	g.dir      = .Down // next head (5,6) is the tail tip, which moves away
	g.next_dir = .Down
	step(&g)
	expect(&fails, g.state == .Playing, "tail-follow move survives")
	expect(&fails, g.len == 4, "tail-follow keeps length")

	// 9. Leaving the grid ends the game.
	reset_game(&g)
	g.snake[0] = Cell{0, 9}
	g.snake[1] = Cell{1, 9}
	g.snake[2] = Cell{2, 9}
	g.len      = 3
	g.dir      = .Left
	g.next_dir = .Left
	step(&g)
	expect(&fails, g.state == .GameOver, "wall collision ends the game")

	if fails == 0 {
		fmt.println("SELFTEST PASS")
	} else {
		fmt.printf("SELFTEST FAIL (%d)\n", fails)
		os.exit(1)
	}
}

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "selftest" {
		selftest()
		return
	}

	rl.SetConfigFlags({ rl.ConfigFlag.VSYNC_HINT })
	rl.InitWindow(WINDOW_W, WINDOW_H, "Snake - Odin + raylib")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	rand.reset(cast(u64) time.to_unix_nanoseconds(time.now()))

	g: Game
	reset_game(&g)

	for !rl.WindowShouldClose() {
		update(&g)
		draw(&g)
	}
}
