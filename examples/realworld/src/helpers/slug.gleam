import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/string
import sqlight

pub fn from_title(title: String) -> String {
  title
  |> string.lowercase
  |> string.to_graphemes
  |> normalize_slug_chars(graphemes: _, previous_was_dash: True, acc: "")
  |> strip_char("-")
}

pub fn unique_from_title(
  db db: sqlight.Connection,
  title title: String,
) -> String {
  let base = from_title(title)
  unique_slug_loop(db: db, base: base, counter: 0, exclude_params: [])
}

pub fn unique_from_title_excluding(
  db db: sqlight.Connection,
  title title: String,
  article_id article_id: Int,
) -> String {
  let base = from_title(title)
  unique_slug_loop(db: db, base: base, counter: 0, exclude_params: [
    sqlight.int(article_id),
  ])
}

fn unique_slug_loop(
  db db: sqlight.Connection,
  base base: String,
  counter counter: Int,
  exclude_params exclude_params: List(sqlight.Value),
) -> String {
  let candidate = case counter {
    0 -> base
    n -> base <> "-" <> int.to_string(n)
  }
  case slug_exists(db: db, slug: candidate, exclude_params: exclude_params) {
    True ->
      unique_slug_loop(
        db: db,
        base: base,
        counter: counter + 1,
        exclude_params: exclude_params,
      )
    False -> candidate
  }
}

fn slug_exists(
  db db: sqlight.Connection,
  slug slug: String,
  exclude_params exclude_params: List(sqlight.Value),
) -> Bool {
  let #(query, params) = case exclude_params {
    [] -> #("SELECT 1 FROM articles WHERE slug = ?1 LIMIT 1", [
      sqlight.text(slug),
    ])
    _ -> #("SELECT 1 FROM articles WHERE slug = ?1 AND id != ?2 LIMIT 1", [
      sqlight.text(slug),
      ..exclude_params
    ])
  }
  case
    sqlight.query(query, on: db, with: params, expecting: decode.success(Nil))
  {
    Ok([_]) -> True
    _ -> False
  }
}

fn strip_char(s: String, char: String) -> String {
  s
  |> strip_leading(char)
  |> strip_trailing(char)
}

fn normalize_slug_chars(
  graphemes graphemes: List(String),
  previous_was_dash previous_was_dash: Bool,
  acc acc: String,
) -> String {
  case graphemes {
    [] -> acc
    [grapheme, ..rest] -> {
      let #(next_acc, next_previous_was_dash) =
        next_slug_state(
          grapheme: grapheme,
          previous_was_dash: previous_was_dash,
          acc: acc,
        )
      normalize_slug_chars(
        graphemes: rest,
        previous_was_dash: next_previous_was_dash,
        acc: next_acc,
      )
    }
  }
}

fn next_slug_state(
  grapheme grapheme: String,
  previous_was_dash previous_was_dash: Bool,
  acc acc: String,
) -> #(String, Bool) {
  use <- bool.guard(when: is_slug_char(grapheme), return: #(
    acc <> grapheme,
    False,
  ))
  case previous_was_dash {
    True -> #(acc, True)
    False -> #(acc <> "-", True)
  }
}

fn is_slug_char(grapheme: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789", grapheme)
}

fn strip_leading(s: String, prefix: String) -> String {
  use <- bool.guard(when: !string.starts_with(s, prefix), return: s)
  strip_leading(string.drop_start(s, string.length(prefix)), prefix)
}

fn strip_trailing(s: String, suffix: String) -> String {
  use <- bool.guard(when: !string.ends_with(s, suffix), return: s)
  strip_trailing(string.drop_end(s, string.length(suffix)), suffix)
}
