import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/regexp
import gleam/string
import sqlight

pub fn from_title(title: String) -> String {
  let assert Ok(re) = regexp.from_string("[^a-z0-9]+")
  title
  |> string.lowercase
  |> regexp.replace(re, _, "-")
  |> strip_char("-")
}

pub fn unique_from_title(db: sqlight.Connection, title: String) -> String {
  let base = from_title(title)
  unique_slug_loop(db, base, 0, [])
}

pub fn unique_from_title_excluding(
  db: sqlight.Connection,
  title: String,
  article_id: Int,
) -> String {
  let base = from_title(title)
  unique_slug_loop(db, base, 0, [sqlight.int(article_id)])
}

fn unique_slug_loop(
  db: sqlight.Connection,
  base: String,
  counter: Int,
  exclude_params: List(sqlight.Value),
) -> String {
  let candidate = case counter {
    0 -> base
    n -> base <> "-" <> int.to_string(n)
  }
  case slug_exists(db, candidate, exclude_params) {
    True -> unique_slug_loop(db, base, counter + 1, exclude_params)
    False -> candidate
  }
}

fn slug_exists(
  db: sqlight.Connection,
  slug: String,
  exclude_params: List(sqlight.Value),
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

fn strip_leading(s: String, prefix: String) -> String {
  use <- bool.guard(when: !string.starts_with(s, prefix), return: s)
  strip_leading(string.drop_start(s, string.length(prefix)), prefix)
}

fn strip_trailing(s: String, suffix: String) -> String {
  use <- bool.guard(when: !string.ends_with(s, suffix), return: s)
  strip_trailing(string.drop_end(s, string.length(suffix)), suffix)
}
