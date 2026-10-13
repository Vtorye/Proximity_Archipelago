1. `get_tree().create_timer(t)` defaults to `process_always = true`. It keeps firing while paused. If you use it in gameplay code, pass false explicitly:
```gdscript
await get_tree().create_timer(0.3, false).timeout
```

2. `get_tree().create_tween()` ignores pause. Always use `node.create_tween()`, because the tween inherits the node's process mode

3. Autoloads inherit pausability from root. If your future `AudioManager` fades music with a tween, set `process_mode = PROCESS_MODE_ALWAYS` in its `_ready()`

4. `await` in `_ready()` works but makes `_ready` `async`. `Router.goto` awaits the fade, so `Boot._ready` returns before the first screen is visible

5. Payload must be set before `add_child`. If you move the `_current.payload = payload` line after `add_child`, `_ready()` in the screen won't see it

6. Hidden menus still receive input unless you guard for it. That's why `MenuBase._unhandled_input` starts with `if not visible: return`

7. `process_mode` is set in the Inspector, not the script, for the shell layers. If you set it in code, make sure it runs before anything can pause - `_enter_tree()` is safe, `_ready()` is too late for the very first frame in edge cases
