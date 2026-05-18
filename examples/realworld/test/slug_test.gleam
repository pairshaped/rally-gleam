import gleeunit/should
import helpers/slug

pub fn simple_title_test() {
  slug.from_title("Hello World")
  |> should.equal("hello-world")
}

pub fn special_characters_test() {
  slug.from_title("What's New?")
  |> should.equal("what-s-new")
}

pub fn multiple_spaces_test() {
  slug.from_title("Too   Many   Spaces")
  |> should.equal("too-many-spaces")
}

pub fn leading_trailing_test() {
  slug.from_title("  Hello  ")
  |> should.equal("hello")
}

pub fn numbers_preserved_test() {
  slug.from_title("Article 123")
  |> should.equal("article-123")
}
