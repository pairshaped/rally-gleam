//// Client package codec and page module generator.
////
//// Generates:
//// - codec_ffi.mjs — JS typed decoders (from walker-discovered types)
//// - types.gleam — ClientMsg type for RPC dispatch
//// - codec.gleam — decode_flags utility
//// - Per-page client modules — tree-shaken page source
//// - rally/runtime/effect.gleam — client-side effect shim

import glance
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import justin
import libero/codegen
import libero/codegen_decoders
import libero/field_type.{
  type FieldType, BitArrayField, BoolField, DictOf, FloatField, IntField, ListOf,
  NilField, OptionOf, ResultOf, StringField, TupleOf, TypeVar, UserType,
}
import libero/json/codegen as json_codegen
import libero/scanner.{type HandlerEndpoint}
import libero/walker
import rally/internal/tree_shaker
import rally/internal/types.{
  type PageContract, type ScannedRoute, type VariantInfo,
}

pub type CodecFile {
  CodecFile(path: String, content: String)
}

/// Generate all codec files for the client package.
pub fn generate(
  contracts contracts: List(#(ScannedRoute, PageContract)),
  discovered discovered: List(walker.DiscoveredType),
  endpoints endpoints: List(HandlerEndpoint),
  server_symbols server_symbols: List(String),
  protocol protocol: String,
) -> List(CodecFile) {
  case
    generate_result(
      contracts:,
      discovered:,
      endpoints:,
      server_symbols:,
      protocol:,
    )
  {
    Ok(files) -> files
    Error(message) -> {
      io.println_error("Codec generation failed: " <> message)
      []
    }
  }
}

fn generate_result(
  contracts contracts: List(#(ScannedRoute, PageContract)),
  discovered discovered: List(walker.DiscoveredType),
  endpoints endpoints: List(HandlerEndpoint),
  server_symbols server_symbols: List(String),
  protocol protocol: String,
) -> Result(List(CodecFile), String) {
  use types_gleam <- result.try(emit_types_gleam(contracts, endpoints, protocol))
  let codec_files = [
    CodecFile(
      "src/generated/codec_ffi.mjs",
      emit_codec_ffi_with_endpoints(discovered, endpoints),
    ),
    CodecFile("src/generated/types.gleam", types_gleam),
    CodecFile("src/generated/codec.gleam", emit_codec_gleam(protocol)),
    CodecFile(
      "src/rally/runtime/effect.gleam",
      emit_rally_effect_shim(protocol),
    ),
    CodecFile("src/rally/runtime/rally_effect_ffi.mjs", emit_rally_effect_ffi()),
  ]

  use page_files <- result.try(generate_page_modules_result(
    contracts,
    server_symbols,
    protocol,
  ))

  Ok(list.append(codec_files, page_files))
}

/// Generate per-page client modules from tree-shaken source.
fn generate_page_modules_result(
  contracts: List(#(ScannedRoute, PageContract)),
  server_symbols: List(String),
  protocol: String,
) -> Result(List(CodecFile), String) {
  use files <- result.try(
    list.try_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case contract.has_model {
        False -> Ok(option.None)
        True -> {
          let shaken = tree_shaker.shake(contract.source, server_symbols:)
          let page_path = page_module_path(route.module_path)
          use content <- result.try(post_process_page_result(
            shaken,
            route.variant_name,
            protocol,
            contract,
            route.module_path,
          ))
          Ok(option.Some(CodecFile("src/" <> page_path <> ".gleam", content)))
        }
      }
    }),
  )
  Ok(
    list.filter_map(files, fn(file) {
      case file {
        option.Some(file) -> Ok(file)
        option.None -> Error(Nil)
      }
    }),
  )
}

/// Generate JSON typed encoder/decoder source for the client package.
/// Uses libero's JSON codegen to produce per-type json.Json builders
/// and typed decoders for all discovered types.
pub fn generate_json_codecs(
  discovered discovered: List(walker.DiscoveredType),
  endpoints _endpoints: List(HandlerEndpoint),
) -> List(CodecFile) {
  case json_codegen.generate(discovered) {
    Ok(content) -> [
      CodecFile("src/generated/json_codecs.gleam", content),
      generate_json_decode_dispatch(discovered),
      generate_json_type_registry_js(discovered),
    ]
    Error(errors) -> {
      list.each(errors, fn(e) {
        io.println_error("JSON codegen error: " <> e.path <> ": " <> e.message)
      })
      []
    }
  }
}

/// Generate a Gleam module that dispatches decoder names to the
/// corresponding JSON typed decoders at runtime.
///
/// The decoder_name follows the ETF codec convention
/// (e.g. "decode_pages_home__model") and is mapped to the
/// `json_decode_<qualified_atom_name>` function in json_codecs.
pub fn generate_json_decode_dispatch(
  discovered: List(walker.DiscoveredType),
) -> CodecFile {
  let cases =
    list.map(discovered, fn(dt) {
      let qual = walker.qualified_atom_name(dt.module_path, dt.type_name)
      "    \"decode_"
      <> qual
      <> "\" -> result.map(json_codecs.json_decode_"
      <> qual
      <> "(value), identity)"
    })

  let body = "// Generated by Rally — do not edit.
////
//// JSON typed decode dispatch. Routes decoder names to the
//// corresponding typed decoders generated by libero JSON codegen.

import gleam/dynamic.{type Dynamic}
import gleam/result
import generated/json_codecs as json_codecs
import libero/json/error.{type JsonError, JsonError}

@external(javascript, \"./protocol_wire.mjs\", \"identity\")
fn identity(value: a) -> b

/// Decode a Dynamic value using the named typed decoder.
/// The decoder_name follows the pattern decode_<module>__<type>,
/// matching the ETF codec naming convention.
pub fn decode_json_typed(
  value: Dynamic,
  decoder_name: String,
) -> Result(Dynamic, List(JsonError)) {
  case decoder_name {
" <> string.join(cases, "\n") <> "\n    _ -> Error([JsonError(\"decoder\", \"unknown: \" <> decoder_name)])
  }
}
"

  CodecFile("src/generated/json_decode_dispatch.gleam", body)
}

/// Generate a JS type registry that maps "<module>.<type>#<variant>"
/// identities to Gleam JS constructors. The registry is imported by
/// protocol_wire.mjs and used in typedJsonToGleamValue to produce
/// properly typed instances instead of generic CustomType objects.
///
/// Keys include the parent type name so a mismatched "type" field
/// (e.g. { type: "some/module.OldType", variant: "Discount" }) never
/// resolves to the registry entry for "some/module.Discount#Discount".
fn next_unused_alias(
  used: dict.Dict(String, Nil),
  candidate: String,
  n: Int,
) -> String {
  let alias = case n {
    -1 -> candidate
    _ -> candidate <> "_" <> int.to_string(n)
  }
  case dict.has_key(used, alias) {
    False -> alias
    True -> next_unused_alias(used, candidate, n + 1)
  }
}

/// Build a collision-safe mapping from module_path to JS import alias.
/// Maintains a global used-aliases set. For each module the clean
/// candidate is tried first; if already taken, `_0`, `_1`, ... suffixes
/// are appended until an unused alias is found. This handles both
/// slash/underscore collisions (`admin/foo_bar/baz` vs `admin/foo/bar_baz`)
/// and suffix-poisoning (`admin/foo/bar_0` vs a suffixed `admin/foo/bar`).
fn build_module_aliases(modules: List(String)) -> dict.Dict(String, String) {
  let #(_, aliases) =
    list.fold(modules, #(dict.new(), dict.new()), fn(state, mod) {
      let #(used, aliases) = state
      let candidate = "_m_" <> string.replace(mod, "/", "_")
      let alias = next_unused_alias(used, candidate, -1)
      let used = dict.insert(used, alias, Nil)
      let aliases = dict.insert(aliases, mod, alias)
      #(used, aliases)
    })
  aliases
}

pub fn generate_json_type_registry_js(
  discovered: List(walker.DiscoveredType),
) -> CodecFile {
  let modules =
    discovered
    |> list.map(fn(dt) { dt.module_path })
    |> list.unique

  let aliases = build_module_aliases(modules)

  let imports = case modules {
    [] -> ""
    _ ->
      list.map(modules, fn(mod) {
        let alias = case dict.get(aliases, mod) {
          Ok(a) -> a
          Error(Nil) -> "_m_" <> string.replace(mod, "/", "_")
        }
        "import * as " <> alias <> " from \"../../client/" <> mod <> ".mjs\";"
      })
      |> string.join("\n")
  }

  let entries =
    list.flat_map(discovered, fn(dt) {
      let mod_alias = case dict.get(aliases, dt.module_path) {
        Ok(a) -> a
        Error(Nil) -> "_m_" <> string.replace(dt.module_path, "/", "_")
      }
      list.map(dt.variants, fn(v) {
        let key = dt.module_path <> "." <> dt.type_name <> "#" <> v.variant_name
        let ctor_expr = case v.fields {
          [] -> "() => new " <> mod_alias <> "." <> v.variant_name <> "()"
          _ -> {
            let all_labelled =
              list.all(v.field_labels, fn(l) { l != option.None })
            case all_labelled {
              True -> {
                let args =
                  list.filter_map(list.zip(v.fields, v.field_labels), fn(pair) {
                    let #(_, label) = pair
                    case label {
                      option.Some(name) -> Ok("fields." <> name)
                      option.None -> Error(Nil)
                    }
                  })
                  |> string.join(", ")
                "(fields) => new "
                <> mod_alias
                <> "."
                <> v.variant_name
                <> "("
                <> args
                <> ")"
              }
              False -> {
                let args =
                  list.index_map(v.fields, fn(_, i) {
                    "fields[" <> int.to_string(i) <> "]"
                  })
                  |> string.join(", ")
                "(fields) => new "
                <> mod_alias
                <> "."
                <> v.variant_name
                <> "("
                <> args
                <> ")"
              }
            }
          }
        }
        "  \"" <> key <> "\": " <> ctor_expr <> ","
      })
    })
    |> string.join("\n")

  let body =
    "// Generated by Rally — do not edit.\n"
    <> "// Type registry for JSON decode path.\n"
    <> "// Maps \"<module>.<type>#<variant>\" identities to Gleam JS constructors.\n"
    <> "\n"
    <> imports
    <> "\n\n"
    <> "export const typeRegistry = {\n"
    <> entries
    <> "\n};\n"

  CodecFile("src/generated/type_registry.mjs", body)
}

/// Convert a server module path to a client page path.
/// "pages/home_" -> "pages/home_"
/// "pages/article/slug_" -> "pages/article/slug_"
fn page_module_path(module_path: String) -> String {
  module_path
}

/// Post-process tree-shaken source for client usage:
/// - Replace rally_effect.send_to_server with local wrapper
/// - Add transport import and local send_to_server wrapper
/// - For JSON protocol, generate json_encode_msg for page Msg type
fn post_process_page_result(
  source: String,
  variant_name: String,
  protocol: String,
  contract: PageContract,
  page_module_path: String,
) -> Result(String, String) {
  let effect_aliases = effect_module_aliases(source)
  let has_send_to_server =
    list.any(effect_aliases, fn(alias) {
      string.contains(source, alias <> ".send_to_server(")
      || string.contains(source, alias <> ".send_to_server (")
    })

  use json_msg_encoder <- result.try(case protocol, contract.msg_variants {
    "json", [] -> Ok("")
    "json", _ -> {
      use encoder <- result.try(generate_json_page_msg_encoder_result(
        contract.msg_variants,
        page_module_path,
      ))
      let has_user_type =
        list.any(contract.msg_variants, fn(v) {
          list.any(v.fields, fn(f) {
            case f.type_ {
              field_type.UserType(..) -> True
              _ -> False
            }
          })
        })
      case has_user_type {
        True -> Ok("import generated/json_codecs as json_codecs\n\n" <> encoder)
        False -> Ok(encoder)
      }
    }
    _, _ -> Ok("")
  })

  let wrapper = case has_send_to_server {
    True -> {
      let transport_import = "\nimport generated/transport\n"
      let json_import = case protocol {
        "json" -> "import gleam/json\n"
        _ -> ""
      }
      let encoded_msg = case protocol {
        "json" -> "json_encode_msg(msg)"
        _ -> "msg"
      }
      transport_import
      <> json_import
      <> "\nfn send_to_server(msg: a) -> effect.Effect(b) {\n"
      <> "  effect.from(fn(_dispatch) {\n"
      <> "    transport.send_to_server(\""
      <> variant_name
      <> "\", "
      <> encoded_msg
      <> ")\n"
      <> "    Nil\n"
      <> "  })\n"
      <> "}\n"
      <> json_msg_encoder
    }
    False -> ""
  }

  Ok(
    source
    |> replace_send_to_server_calls(effect_aliases)
    |> drop_unused_effect_import(effect_aliases)
    |> fn(s) { s <> wrapper },
  )
}

fn generate_json_page_msg_encoder_result(
  variants: List(VariantInfo),
  page_module_path: String,
) -> Result(String, String) {
  use arms <- result.try(
    list.try_map(variants, fn(v) {
      let type_id = page_module_path <> ".Msg"
      use fields <- result.try(case v.fields {
        [] -> Ok("json.object([])")
        _ -> {
          use pairs <- result.try(
            list.try_map(v.fields, fn(f) {
              use encoder <- result.try(json_primitive_encoder(f.type_, f.label))
              Ok("#(\"" <> f.label <> "\", " <> encoder <> ")")
            }),
          )
          Ok("json.object([" <> string.join(pairs, ", ") <> "])")
        }
      })
      Ok(
        "    "
        <> v.name
        <> " -> json.object([\n"
        <> "      #(\"type\", json.string(\""
        <> type_id
        <> "\")),\n"
        <> "      #(\"variant\", json.string(\""
        <> v.name
        <> "\")),\n"
        <> "      #(\"fields\", "
        <> fields
        <> "),\n"
        <> "    ])",
      )
    }),
  )
  Ok(
    "\npub fn json_encode_msg(msg: Msg) -> json.Json {\n  case msg {\n"
    <> string.join(arms, "\n")
    <> "\n  }\n}\n",
  )
}

fn effect_module_aliases(source: String) -> List(String) {
  case glance.module(source) {
    Error(glance.UnexpectedEndOfInput) -> ["rally_effect"]
    Error(glance.UnexpectedToken(..)) -> ["rally_effect"]
    Ok(ast) ->
      ast.imports
      |> list.filter_map(fn(def) {
        let import_ = def.definition
        case import_.module == "rally/runtime/effect" {
          False -> Error(Nil)
          True ->
            case import_.alias {
              option.Some(glance.Named(name)) -> Ok(name)
              _ -> Ok("effect")
            }
        }
      })
      |> fn(aliases) {
        case aliases {
          [] -> ["rally_effect"]
          _ -> aliases
        }
      }
  }
}

fn replace_send_to_server_calls(
  source: String,
  aliases: List(String),
) -> String {
  list.fold(aliases, source, fn(acc, alias) {
    acc
    |> string.replace(alias <> ".send_to_server(", "send_to_server(")
    |> string.replace(alias <> ".send_to_server (", "send_to_server (")
  })
}

fn drop_unused_effect_import(source: String, aliases: List(String)) -> String {
  let alias_still_used =
    list.any(aliases, fn(alias) { string.contains(source, alias <> ".") })
  case alias_still_used {
    True -> source
    False ->
      source
      |> string.split("\n")
      |> list.filter(fn(line) {
        !string.starts_with(string.trim(line), "import rally/runtime/effect")
      })
      |> string.join("\n")
  }
}

/// Extract (module_path, type_name) seeds from a client_context.gleam
/// source so the walker can discover ClientContext types with proper
/// field type resolution, instead of the old hardcoded-StringField path.
pub fn client_context_seeds(
  source source: String,
  module_path module_path: String,
) -> List(#(String, String)) {
  case glance.module(source) {
    Error(glance.UnexpectedEndOfInput) -> []
    Error(glance.UnexpectedToken(..)) -> []
    Ok(ast) ->
      list.map(ast.custom_types, fn(def) { #(module_path, def.definition.name) })
  }
}

fn emit_rally_effect_shim(protocol: String) -> String {
  let rpc_fn = case protocol {
    "json" ->
      "
pub fn rpc(msg: a, on_response on_response: fn(b) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    transport.send_rpc(types.json_encode_client_msg(transport.coerce(msg)), fn(response) {
      dispatch(on_response(transport.coerce(response)))
    })
  })
}
"
    _ ->
      "
pub fn rpc(msg: a, on_response on_response: fn(b) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    transport.send_rpc(msg, fn(response) {
      dispatch(on_response(response))
    })
  })
}
"
  }

  let client_context_fn = case protocol {
    "json" ->
      "
pub fn send_to_client_context(_msg: a) -> Effect(b) {
  panic as \"send_to_client_context: JSON client context encoding is not yet implemented\"
}
"
    _ ->
      "
pub fn send_to_client_context(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    transport.send_to_server(\"__ClientContext__\", msg)
    Nil
  })
}
"
  }

  let imports = case protocol {
    "json" -> "import generated/transport\nimport generated/types\n\n"
    _ -> "import generated/transport\n\n"
  }

  imports <> "// Generated by Rally — do not edit.
////
//// Client-side effect shim. Provides the same API as
//// rally/runtime/effect but backed by the client transport.

import lustre/effect.{type Effect}" <> rpc_fn <> client_context_fn <> "
pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_navigate(path)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"navigate\")
fn do_navigate(_path: String) -> Nil {
  Nil
}

pub fn none() -> Effect(a) {
  effect.none()
}

pub fn get_ws_session() -> String {
  \"\"
}

pub fn set_dark_mode(enabled: Bool) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_set_dark_mode(enabled)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"setDarkMode\")
fn do_set_dark_mode(_enabled: Bool) -> Nil {
  Nil
}

pub fn set_lang(lang: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_set_lang(lang)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"setLang\")
fn do_set_lang(_lang: String) -> Nil {
  Nil
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"readDarkModeCookie\")
pub fn read_dark_mode() -> Bool {
  False
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"readLangCookie\")
pub fn read_lang() -> String {
  \"\"
}
"
}

fn emit_rally_effect_ffi() -> String {
  "// Generated by Rally — do not edit.

export function navigate(path) {
  globalThis.history?.pushState(null, \"\", path);
  globalThis.dispatchEvent(new PopStateEvent(\"popstate\"));
}

export function setDarkMode(enabled) {
  document.documentElement.classList.toggle(\"dark\", enabled);
  document.cookie = \"__rally_dark_mode=\" + (enabled ? \"1\" : \"0\") + \";path=/;max-age=31536000;SameSite=Lax\";
}

export function setLang(lang) {
  document.cookie = \"__rally_lang=\" + lang + \";path=/;max-age=31536000;SameSite=Lax\";
}

export function readDarkModeCookie() {
  var c = document.cookie;
  if (c.includes('__rally_dark_mode=1')) return true;
  if (c.includes('__rally_dark_mode=0')) return false;
  return window.matchMedia('(prefers-color-scheme:dark)').matches;
}

export function readLangCookie() {
  var m = document.cookie.match(/(?:^|;)\\s*__rally_lang=([^;]+)/);
  if (m) return m[1];
  var lang = navigator.language || navigator.userLanguage || '';
  return lang ? lang.split('-')[0] : 'en';
}
"
}

// ---------- JS typed decoders (codec_ffi.mjs) ----------

fn emit_codec_ffi_with_endpoints(
  discovered: List(walker.DiscoveredType),
  endpoints: List(HandlerEndpoint),
) -> String {
  codegen_decoders.generate_decoders_ffi(
    discovered:,
    endpoints:,
    relpath_prefix: "../../",
    package: "client",
    dependency_packages: [],
    dispatch_module: option.Some("generated/types"),
  )
}

// ---------- Mirrored types (types.gleam) ----------

fn emit_types_gleam(
  _contracts: List(#(ScannedRoute, PageContract)),
  endpoints: List(HandlerEndpoint),
  protocol: String,
) -> Result(String, String) {
  let resolve_alias = build_type_alias_resolver(endpoints)

  let client_msg_type = case endpoints {
    [] -> ""
    _ -> {
      let variants =
        list.map(endpoints, fn(e) {
          let variant_name = justin.pascal_case("server_" <> e.fn_name)
          case e.params {
            [] -> "  " <> variant_name
            params -> {
              let fields =
                list.map(params, fn(p) {
                  p.0
                  <> ": "
                  <> field_type.to_gleam_source_with_alias(p.1, resolve_alias)
                })
              "  " <> variant_name <> "(" <> string.join(fields, ", ") <> ")"
            }
          }
        })
      "\npub type ClientMsg {\n" <> string.join(variants, "\n") <> "\n}\n"
    }
  }

  use json_encode_fn <- result.try(case protocol {
    "json" ->
      case endpoints {
        [] -> Ok("")
        _ -> {
          let json_import = "import gleam/json\n"
          use arms <- result.try(
            list.try_map(endpoints, fn(e) {
              let variant_name = justin.pascal_case("server_" <> e.fn_name)
              case e.msg_type {
                option.Some(#(type_module, type_name)) -> {
                  let param_pattern = case e.params {
                    [] -> ""
                    params -> {
                      "("
                      <> string.join(
                        list.map(params, fn(p) { p.0 <> ": " <> p.0 }),
                        ", ",
                      )
                      <> ")"
                    }
                  }
                  use field_encoders <- result.try(case e.params {
                    [] -> Ok("json.object([])")
                    params -> {
                      use pairs <- result.try(
                        list.try_map(params, fn(p) {
                          use encoder <- result.try(json_primitive_encoder(
                            p.1,
                            p.0,
                          ))
                          Ok("#(\"" <> p.0 <> "\", " <> encoder <> ")")
                        }),
                      )
                      Ok("json.object([" <> string.join(pairs, ", ") <> "])")
                    }
                  })
                  Ok(
                    variant_name
                    <> param_pattern
                    <> " -> json.object([\n"
                    <> "        #(\"type\", json.string(\""
                    <> type_module
                    <> "."
                    <> type_name
                    <> "\")),\n"
                    <> "        #(\"variant\", json.string(\""
                    <> type_name
                    <> "\")),\n"
                    <> "        #(\"fields\", "
                    <> field_encoders
                    <> "),\n"
                    <> "      ])",
                  )
                }
                option.None -> {
                  use field_encoders <- result.try(
                    list.try_map(e.params, fn(p) {
                      use encoder <- result.try(json_primitive_encoder(p.1, p.0))
                      Ok("#(\"" <> p.0 <> "\", " <> encoder <> ")")
                    }),
                  )
                  Ok(
                    variant_name
                    <> "("
                    <> string.join(
                      list.map(e.params, fn(p) { p.0 <> ": " <> p.0 }),
                      ", ",
                    )
                    <> ") -> json.object([\n"
                    <> "        #(\"type\", json.string(\""
                    <> e.module_path
                    <> "."
                    <> justin.pascal_case("server_" <> e.fn_name)
                    <> "\")),\n"
                    <> "        #(\"variant\", json.string(\""
                    <> justin.pascal_case("server_" <> e.fn_name)
                    <> "\")),\n"
                    <> "        #(\"fields\", json.object(["
                    <> string.join(field_encoders, ", ")
                    <> "])),\n"
                    <> "      ])",
                  )
                }
              }
            }),
          )
          Ok(
            json_import
            <> "\npub fn json_encode_client_msg(msg: ClientMsg) -> json.Json {\n  case msg {\n    "
            <> string.join(arms, "\n")
            <> "\n  }\n}\n",
          )
        }
      }
    _ -> Ok("")
  })

  let all_modules =
    endpoints
    |> list.flat_map(fn(e) {
      list.flat_map(e.params, fn(p) { collect_user_type_modules(p.1) })
    })
    |> list.unique

  let type_imports =
    all_modules
    |> list.map(fn(mod) {
      let alias = resolve_alias(mod)
      case alias == field_type.last_segment(mod) {
        True -> "import " <> mod
        False -> "import " <> mod <> " as " <> alias
      }
    })
    |> string.join("\n")
    |> fn(s) {
      case s {
        "" -> ""
        _ -> s <> "\n"
      }
    }

  let option_import =
    codegen.import_if(
      endpoints:,
      predicate: codegen.is_option,
      import_line: "import gleam/option.{type Option}",
    )
  let dict_import =
    codegen.import_if(
      endpoints:,
      predicate: codegen.is_dict,
      import_line: "import gleam/dict.{type Dict}",
    )

  Ok("// Generated by Rally — do not edit.
////
//// Mirrored page types for the client package.

" <> type_imports <> option_import <> dict_import <> client_msg_type <> "\n" <> json_encode_fn)
}

/// Build a resolver that uses the last segment when unique, or the full
/// underscored path when two modules share the same last segment.
fn build_type_alias_resolver(
  endpoints: List(HandlerEndpoint),
) -> fn(String) -> String {
  let all_modules =
    endpoints
    |> list.flat_map(fn(e) {
      list.flat_map(e.params, fn(p) { collect_user_type_modules(p.1) })
    })
    |> list.unique()
  let segment_counts =
    list.fold(all_modules, dict.new(), fn(acc, mod) {
      let seg = field_type.last_segment(mod)
      let count = case dict.get(acc, seg) {
        Ok(n) -> n + 1
        Error(Nil) -> 1
      }
      dict.insert(acc, seg, count)
    })
  fn(module_path: String) -> String {
    let seg = field_type.last_segment(module_path)
    case dict.get(segment_counts, seg) {
      Ok(n) if n > 1 -> string.replace(module_path, "/", "_")
      _ -> seg
    }
  }
}

fn collect_user_type_modules(ft: FieldType) -> List(String) {
  case ft {
    UserType(module_path:, ..) -> [module_path]
    field_type.ListOf(inner) -> collect_user_type_modules(inner)
    field_type.OptionOf(inner) -> collect_user_type_modules(inner)
    field_type.ResultOf(ok, err) ->
      list.append(collect_user_type_modules(ok), collect_user_type_modules(err))
    field_type.DictOf(k, v) ->
      list.append(collect_user_type_modules(k), collect_user_type_modules(v))
    field_type.TupleOf(elems) -> list.flat_map(elems, collect_user_type_modules)
    _ -> []
  }
}

fn json_client_encoder(ft: FieldType, var: String) -> Result(String, String) {
  case ft {
    StringField -> Ok("json.string(" <> var <> ")")
    IntField -> Ok("json.int(" <> var <> ")")
    FloatField -> Ok("json.float(" <> var <> ")")
    BoolField -> Ok("json.bool(" <> var <> ")")
    NilField -> Ok("json.null()")
    BitArrayField ->
      Error("client JSON encoding does not support BitArray fields")
    UserType(module_path:, type_name:, ..) -> {
      let qual = walker.qualified_atom_name(module_path, type_name)
      Ok("json_codecs.json_encode_" <> qual <> "(" <> var <> ")")
    }
    ListOf(inner) -> {
      use encoder <- result.try(json_client_encoder(inner, "x"))
      Ok("json.array(" <> var <> ", of: fn(x) { " <> encoder <> " })")
    }
    OptionOf(inner) -> {
      use encoder <- result.try(json_client_encoder(inner, "x"))
      Ok(
        "(fn(opt) { case opt {"
        <> " None -> json.object([#(\"type\", json.string(\"gleam/option.Option\")), #(\"variant\", json.string(\"None\")), #(\"fields\", json.object([]))])"
        <> " Some(x) -> json.object([#(\"type\", json.string(\"gleam/option.Option\")), #(\"variant\", json.string(\"Some\")), #(\"fields\", json.array(["
        <> encoder
        <> "], of: fn(y) { y }))])"
        <> " } })("
        <> var
        <> ")",
      )
    }
    ResultOf(ok, err) -> {
      use ok_encoder <- result.try(json_client_encoder(ok, "x"))
      use err_encoder <- result.try(json_client_encoder(err, "x"))
      Ok(
        "(fn(res) { case res {"
        <> " Ok(x) -> json.object([#(\"type\", json.string(\"gleam/result.Result\")), #(\"variant\", json.string(\"Ok\")), #(\"fields\", json.array(["
        <> ok_encoder
        <> "], of: fn(y) { y }))])"
        <> " Error(x) -> json.object([#(\"type\", json.string(\"gleam/result.Result\")), #(\"variant\", json.string(\"Error\")), #(\"fields\", json.array(["
        <> err_encoder
        <> "], of: fn(y) { y }))])"
        <> " } })("
        <> var
        <> ")",
      )
    }
    DictOf(_, _) -> Error("client JSON encoding does not support Dict fields")
    TupleOf(_) -> Error("client JSON encoding does not support Tuple fields")
    TypeVar(_) ->
      Error("client JSON encoding does not support type variable fields")
  }
}

fn json_primitive_encoder(
  ft: FieldType,
  var: String,
) -> Result(String, String) {
  json_client_encoder(ft, var)
}

// ---------- Typed codec wrappers (codec.gleam) ----------

fn emit_codec_gleam(protocol: String) -> String {
  case protocol {
    "json" -> json_codec_gleam_content()
    _ -> etf_codec_gleam_content()
  }
}

fn json_codec_gleam_content() -> String {
  "// Generated by Rally — do not edit.
////
//// Typed flags helpers. Parses JSON SSR flags and returns
//// the parsed value. Typed decode is handled by the JS facade
//// (typedJsonToGleamValue) for response/push, and by the
//// generated json_decode_dispatch for SSR model hydration
//// on the server side.

import gleam/dynamic.{type Dynamic}
import gleam/result
import libero/json/error.{type JsonError}

@external(javascript, \"./protocol_wire.mjs\", \"decode_flags_typed\")
fn decode_json_flags(flags: String) -> Result(Dynamic, List(JsonError))

@external(javascript, \"./protocol_wire.mjs\", \"identity\")
fn coerce(value: a) -> b

/// Decode SSR flags from JSON text.
/// Returns the parsed JSON value as Dynamic; the caller
/// type-casts via coerce or uses typedJsonToGleamValue on the JS side.
pub fn decode_flags_typed(
  flags: String,
  _decoder_name: String,
) -> Result(a, List(JsonError)) {
  use parsed <- result.try(decode_json_flags(flags))
  Ok(coerce(parsed))
}
"
}

fn etf_codec_gleam_content() -> String {
  "// Generated by Rally — do not edit.
////
//// Typed flags helpers. Delegates to Libero for the actual
//// base64 + ETF + typed decode pipeline.

import libero/error.{type DecodeError}
import libero/wire

/// Decode SSR flags and apply a typed decoder in one call.
/// The decoder_name is the function name in codec_ffi.mjs,
/// e.g. \"decode_pages_home__model\".
pub fn decode_flags_typed(
  flags: String,
  decoder_name: String,
) -> Result(a, DecodeError) {
  wire.decode_flags_typed(flags:, decoder_name:)
}
"
}
