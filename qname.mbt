///|
/// Expanded XML qualified name. The empty namespace is retained for
/// no-namespace documents and unprefixed attributes.
pub(all) struct QName {
  namespace_uri : String
  local_name : String
} derive(Eq, @debug.Debug)

///|
pub fn QName::new(
  namespace_uri : String,
  local_name : String,
) -> Result[QName, XbrlError] {
  if local_name == "" {
    return Err(InvalidQName("local name is empty", 0))
  }
  if has_xml_space(local_name) {
    return Err(InvalidQName("local name contains whitespace", 0))
  }
  Ok({ namespace_uri, local_name, })
}

///|
pub fn QName::expanded(self : QName) -> String {
  if self.namespace_uri == "" {
    self.local_name
  } else {
    "{" + self.namespace_uri + "}" + self.local_name
  }
}

///|
pub fn QName::matches(
  self : QName,
  namespace_uri : String,
  local_name : String,
) -> Bool {
  self.namespace_uri == namespace_uri && self.local_name == local_name
}

///|
pub fn QName::local_part(self : QName) -> String {
  self.local_name
}

///|
pub fn QName::namespace_uri(self : QName) -> String {
  self.namespace_uri
}

///|
pub(all) struct NamespaceBinding {
  prefix : String
  uri : String
} derive(Eq, @debug.Debug)

///|
pub fn NamespaceBinding::new(prefix : String, uri : String) -> NamespaceBinding {
  { prefix, uri, }
}

///|
fn has_xml_space(value : StringView) -> Bool {
  let mut index = 0
  let length = value.length()
  while index < length {
    let code = value.at(index)
    if code == 32 || code == 9 || code == 10 || code == 13 {
      return true
    }
    index += 1
  }
  false
}

///|
fn split_lexical_qname(
  value : StringView,
) -> Result[(String, String), XbrlError] {
  let length = value.length()
  if length == 0 {
    return Err(InvalidQName("qualified name is empty", 0))
  }
  let mut colon = -1
  let mut index = 0
  while index < length {
    if value.at(index) == 58 {
      if colon >= 0 {
        return Err(InvalidQName("multiple colons", index))
      }
      colon = index
    }
    index += 1
  }
  if colon < 0 {
    Ok(("", value.to_owned()))
  } else if colon == 0 || colon == length - 1 {
    Err(InvalidQName("empty prefix or local name", colon))
  } else {
    Ok(
      (
        value.view(start_offset=0, end_offset=colon).to_owned(),
        value.view(start_offset=colon + 1).to_owned(),
      ),
    )
  }
}

///|
/// Resolves `prefix:local` against a namespace stack encoded as ordered
/// bindings. Later bindings shadow earlier ones. The default namespace applies
/// only to elements, which is why the caller chooses whether to use it.
pub fn resolve_qname(
  lexical : StringView,
  bindings : Array[NamespaceBinding],
  use_default_namespace : Bool,
) -> Result[QName, XbrlError] {
  let (prefix, local_name) = match split_lexical_qname(lexical) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if local_name == "" {
    return Err(InvalidQName("local name is empty", 0))
  }
  let mut uri : String = ""
  let mut found = false
  let mut index = bindings.length() - 1
  while index >= 0 {
    let binding = bindings[index]
    if binding.prefix == prefix {
      uri = binding.uri
      found = true
      break
    }
    index -= 1
  }
  if !found {
    if prefix == "xml" {
      uri = "http://www.w3.org/XML/1998/namespace"
    } else if prefix == "" && !use_default_namespace {
      uri = ""
    } else {
      return Err(MissingNamespace(prefix, 0))
    }
  }
  QName::new(uri, local_name)
}

///|
pub extend QName with Eq::{not_equal, equal}

///|
pub extend QName with @debug.Debug::{to_repr}

///|
pub extend NamespaceBinding with Eq::{not_equal, equal}

///|
pub extend NamespaceBinding with @debug.Debug::{to_repr}
