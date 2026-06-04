import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import libero/field_type.{IntField, UserType}
import libero/walker.{type DiscoveredType, DiscoveredType, DiscoveredVariant}
import rally/internal/generator
import rally/internal/generator/codec.{
  generate_json_codecs, generate_json_decode_dispatch,
  generate_json_type_registry_js,
}
import rally/internal/types.{ClientContextContract, VariantField, VariantInfo}

fn sample_discovered_types() -> List(DiscoveredType) {
  [
    DiscoveredType(
      module_path: "pages/home",
      type_name: "Model",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "pages/home",
          variant_name: "Model",
          atom_name: "model",
          float_field_indices: [],
          field_labels: [option.Some("title"), option.Some("count")],
          fields: [IntField, IntField],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "shared/items",
      type_name: "Item",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "shared/items",
          variant_name: "Item",
          atom_name: "item",
          float_field_indices: [],
          field_labels: [option.Some("name")],
          fields: [IntField],
        ),
      ],
    ),
  ]
}

pub fn empty_json_codecs_returns_base_files_test() {
  let files = generate_json_codecs([], [])
  // Even with empty discovered types, the base codecs module,
  // dispatch module, and type registry are still produced
  // (just with no type cases)
  files |> list.length |> should.equal(3)
  let paths = list.map(files, fn(f) { f.path })
  paths |> list.contains("src/generated/json_codecs.gleam") |> should.be_true()
  paths
  |> list.contains("src/generated/json_decode_dispatch.gleam")
  |> should.be_true()
  paths
  |> list.contains("src/generated/type_registry.mjs")
  |> should.be_true()
}

pub fn dispatch_has_correct_structure_test() {
  let dispatch = generate_json_decode_dispatch(sample_discovered_types())
  dispatch.path |> should.equal("src/generated/json_decode_dispatch.gleam")
  dispatch.content
  |> string.contains("pub fn decode_json_typed")
  |> should.be_true()
  dispatch.content
  |> string.contains("import gleam/dynamic.{type Dynamic}")
  |> should.be_true()
  dispatch.content |> string.contains("import gleam/result") |> should.be_true()
  dispatch.content
  |> string.contains("import generated/json_codecs as json_codecs")
  |> should.be_true()
  dispatch.content
  |> string.contains("import libero/json/error.{type JsonError, JsonError}")
  |> should.be_true()
  dispatch.content
  |> string.contains("fn identity(value: a) -> b")
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_pages_home__model")
  |> should.be_true()
  dispatch.content
  |> string.contains("json_decode_pages_home__model(value)")
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_shared_items__item")
  |> should.be_true()
  dispatch.content
  |> string.contains("json_decode_shared_items__item(value)")
  |> should.be_true()
  dispatch.content
  |> string.contains(
    "_ -> Error([JsonError(\"decoder\", \"unknown: \" <> decoder_name)])",
  )
  |> should.be_true()
  dispatch.content
  |> string.contains("Result(Dynamic, List(JsonError))")
  |> should.be_true()
}

pub fn generate_json_codecs_includes_dispatch_test() {
  let files = generate_json_codecs(sample_discovered_types(), [])
  files |> list.length |> should.equal(3)
  let paths = list.map(files, fn(f) { f.path })
  paths |> list.contains("src/generated/json_codecs.gleam") |> should.be_true()
  paths
  |> list.contains("src/generated/json_decode_dispatch.gleam")
  |> should.be_true()
  paths
  |> list.contains("src/generated/type_registry.mjs")
  |> should.be_true()
}

pub fn json_client_context_encoder_is_generated_test() {
  let client_context =
    ClientContextContract(
      context_variants: [],
      msg_variants: [
        VariantInfo(name: "SignedIn", fields: [
          VariantField(
            label: "user",
            type_: UserType(
              module_path: "public/client_context",
              type_name: "User",
              args: [],
            ),
          ),
        ]),
        VariantInfo(name: "SignedOut", fields: []),
      ],
      has_init: True,
      has_update: True,
    )
  let files =
    codec.generate_with_client_context_contract(
      contracts: [],
      discovered: [],
      endpoints: [],
      server_symbols: [],
      protocol: "json",
      client_context_contract: option.Some(client_context),
      client_context_module: "public/client_context",
    )
  let assert Ok(types_file) =
    list.find(files, fn(f) { f.path == "src/generated/types.gleam" })
  types_file.content
  |> string.contains("pub fn json_encode_client_context_msg")
  |> should.be_true()
  types_file.content
  |> string.contains("\"public/client_context.ClientContextMsg\"")
  |> should.be_true()
  types_file.content
  |> string.contains(
    "json_codecs.json_encode_public_client_context__user(user)",
  )
  |> should.be_true()

  let assert Ok(effect_file) =
    list.find(files, fn(f) { f.path == "src/rally/runtime/effect.gleam" })
  effect_file.content
  |> string.contains(
    "send_to_client_context: JSON client context encoding is not yet implemented",
  )
  |> should.be_false()
  effect_file.content
  |> string.contains("types.json_encode_client_context_msg")
  |> should.be_true()
}

pub fn empty_dispatch_has_no_type_cases_test() {
  let dispatch = generate_json_decode_dispatch([])
  dispatch.path |> should.equal("src/generated/json_decode_dispatch.gleam")
  dispatch.content
  |> string.contains("pub fn decode_json_typed")
  |> should.be_true()
  dispatch.content
  |> string.contains(
    "_ -> Error([JsonError(\"decoder\", \"unknown: \" <> decoder_name)])",
  )
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_pages_home__model")
  |> should.be_false()
  dispatch.content
  |> string.contains("json_decode_pages_home__model")
  |> should.be_false()
}

pub fn type_registry_distinct_cross_module_entries_test() {
  // Two modules with the same variant name (Discount) must produce
  // distinct registry keys so identity is preserved through decode.
  let types = [
    DiscoveredType(
      module_path: "admin/dashboard/discount",
      type_name: "Discount",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/dashboard/discount",
          variant_name: "Discount",
          atom_name: "discount",
          float_field_indices: [],
          field_labels: [option.Some("id")],
          fields: [IntField],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "admin/discounts/discount",
      type_name: "Discount",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/discounts/discount",
          variant_name: "Discount",
          atom_name: "discount",
          float_field_indices: [],
          field_labels: [option.Some("code"), option.Some("cents")],
          fields: [IntField, IntField],
        ),
      ],
    ),
  ]

  let registry = generate_json_type_registry_js(types)

  // Each module path produces a distinct import
  registry.content
  |> string.contains(
    "import * as _m_admin_dashboard_discount from \"../../client/admin/dashboard/discount.mjs\"",
  )
  |> should.be_true()
  registry.content
  |> string.contains(
    "import * as _m_admin_discounts_discount from \"../../client/admin/discounts/discount.mjs\"",
  )
  |> should.be_true()

  // Each variant gets a distinct registry key containing the module path
  // Single-field variant: (fields) => new Class(fields.label)
  registry.content
  |> string.contains(
    "\"admin/dashboard/discount.Discount#Discount\": (fields) => new _m_admin_dashboard_discount.Discount(fields.id)",
  )
  |> should.be_true()
  // Multi-field variant: (fields) => new Class(fields.a, fields.b)
  registry.content
  |> string.contains(
    "\"admin/discounts/discount.Discount#Discount\": (fields) => new _m_admin_discounts_discount.Discount(fields.code, fields.cents)",
  )
  |> should.be_true()

  // Registry is exported as a const
  registry.content
  |> string.contains("export const typeRegistry = {")
  |> should.be_true()
}

pub fn type_registry_marks_zero_field_constructors_test() {
  // Zero-field variants should use () => new ... not (fields) => new ...
  let types = [
    DiscoveredType(
      module_path: "pages/home",
      type_name: "NoArgs",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "pages/home",
          variant_name: "NoArgs",
          atom_name: "no_args",
          float_field_indices: [],
          field_labels: [],
          fields: [],
        ),
      ],
    ),
  ]

  let registry = generate_json_type_registry_js(types)

  registry.content
  |> string.contains(
    "\"pages/home.NoArgs#NoArgs\": () => new _m_pages_home.NoArgs()",
  )
  |> should.be_true()
}

pub fn type_registry_keys_include_parent_type_not_just_variant_test() {
  // A multi-variant type where type_name != variant_name must produce
  // keys that include the parent type name. This prevents an attacker
  // from crafting { type: "some/module.HarmlessType", variant: "Discount" }
  // and having it resolve to the Discount constructor.
  let types = [
    DiscoveredType(
      module_path: "some/module",
      type_name: "Response",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "some/module",
          variant_name: "Discount",
          atom_name: "discount",
          float_field_indices: [],
          field_labels: [option.Some("id")],
          fields: [IntField],
        ),
        DiscoveredVariant(
          module_path: "some/module",
          variant_name: "Refund",
          atom_name: "refund",
          float_field_indices: [],
          field_labels: [option.Some("amount")],
          fields: [IntField],
        ),
      ],
    ),
  ]

  let registry = generate_json_type_registry_js(types)

  // Key includes parent type: module.type_name#variant_name
  registry.content
  |> string.contains(
    "\"some/module.Response#Discount\": (fields) => new _m_some_module.Discount(fields.id)",
  )
  |> should.be_true()

  registry.content
  |> string.contains(
    "\"some/module.Response#Refund\": (fields) => new _m_some_module.Refund(fields.amount)",
  )
  |> should.be_true()

  // Must NOT produce a key keyed by variant alone (the old identity hole)
  registry.content
  |> string.contains("\"some/module.Discount\"")
  |> should.be_false()
}

pub fn type_registry_rejects_mismatched_type_in_lookup_test() {
  // Verify the lookup code uses t + "#" + v, not module + "." + variant.
  // With this format, { type: "some/module.OldType", variant: "Discount" }
  // produces key "some/module.OldType#Discount", which won't match
  // "some/module.Response#Discount" from the registry.

  // We verify this at the generator level: the generated protocol_wire.mjs
  // must not derive the key by stripping the type name off "type".
  let js = generator.generate_protocol_wire_js("json", "test_hash_abc123")

  // The key derivation must use the full "type" field as-is (t + "#" + v)
  js |> string.contains("const key = t + \"#\" + v") |> should.be_true()

  // Must NOT strip the type name (no lastIndexOf-based key derivation)
  js
  |> string.contains("t.substring(0, lastDot) + \".\" + v")
  |> should.be_false()
}

pub fn type_registry_aliases_avoid_slash_underscore_collision_test() {
  // `admin/foo_bar/baz` and `admin/foo/bar_baz` would both produce
  // `_m_admin_foo_bar_baz` with naive underscore replacement. The
  // generator must detect the collision and disambiguate with a suffix.
  let types = [
    DiscoveredType(
      module_path: "admin/foo_bar/baz",
      type_name: "Msg",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/foo_bar/baz",
          variant_name: "Msg",
          atom_name: "msg",
          float_field_indices: [],
          field_labels: [],
          fields: [],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "admin/foo/bar_baz",
      type_name: "Msg",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/foo/bar_baz",
          variant_name: "Msg",
          atom_name: "msg",
          float_field_indices: [],
          field_labels: [option.Some("x")],
          fields: [IntField],
        ),
      ],
    ),
  ]

  let registry = generate_json_type_registry_js(types)

  // First module keeps the clean alias
  registry.content
  |> string.contains("import * as _m_admin_foo_bar_baz from")
  |> should.be_true()

  // Second module gets a suffixed alias
  registry.content
  |> string.contains("import * as _m_admin_foo_bar_baz_0")
  |> should.be_true()

  // Each variant must reference its correct (disambiguated) alias
  registry.content
  |> string.contains(
    "\"admin/foo_bar/baz.Msg#Msg\": () => new _m_admin_foo_bar_baz.Msg()",
  )
  |> should.be_true()
  registry.content
  |> string.contains(
    "\"admin/foo/bar_baz.Msg#Msg\": (fields) => new _m_admin_foo_bar_baz_0.Msg(fields.x)",
  )
  |> should.be_true()
}

pub fn type_registry_aliases_prevent_suffix_poisoning_test() {
  // `admin/foo/bar` and `admin/foo_bar` collide on `_m_admin_foo_bar`.
  // The second gets `_m_admin_foo_bar_0`.  `admin/foo/bar_0` naturally
  // produces `_m_admin_foo_bar_0`, which the second already owns, so
  // it must be disambiguated further.
  let types = [
    DiscoveredType(
      module_path: "admin/foo/bar",
      type_name: "A",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/foo/bar",
          variant_name: "A",
          atom_name: "a",
          float_field_indices: [],
          field_labels: [],
          fields: [],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "admin/foo_bar",
      type_name: "B",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/foo_bar",
          variant_name: "B",
          atom_name: "b",
          float_field_indices: [],
          field_labels: [],
          fields: [],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "admin/foo/bar_0",
      type_name: "C",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "admin/foo/bar_0",
          variant_name: "C",
          atom_name: "c",
          float_field_indices: [],
          field_labels: [],
          fields: [],
        ),
      ],
    ),
  ]

  let registry = generate_json_type_registry_js(types)

  // admin/foo/bar -> clean alias
  registry.content
  |> string.contains("\"admin/foo/bar.A#A\": () => new _m_admin_foo_bar.A()")
  |> should.be_true()

  // admin/foo_bar -> collides -> _0
  registry.content
  |> string.contains("\"admin/foo_bar.B#B\": () => new _m_admin_foo_bar_0.B()")
  |> should.be_true()

  // admin/foo/bar_0 -> candidate _0 already taken -> _0_0
  registry.content
  |> string.contains(
    "\"admin/foo/bar_0.C#C\": () => new _m_admin_foo_bar_0_0.C()",
  )
  |> should.be_true()
}
