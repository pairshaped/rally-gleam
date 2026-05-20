//// Internal server-side effect runner for generated WebSocket handlers.
////
//// This uses Lustre's @internal perform API, verified against Lustre 5.7.x.
//// Keep Rally's Lustre upper bound tight unless Lustre exposes a stable
//// server-side effect runner.

import gleam/dynamic
import lustre/effect.{type Effect}

pub fn perform(effect_: Effect(a)) -> Nil {
  effect.perform(
    effect_,
    fn(_msg) { Nil },
    fn(_name, _payload) { Nil },
    fn(_selector) { Nil },
    // Lustre's root callback must return Dynamic; the server runner has no DOM.
    fn() { dynamic.nil() },
    fn(_key, _value) { Nil },
    fn(_name, _decoder) { Nil },
    fn(_name) { Nil },
  )
}
