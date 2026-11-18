///|
pub(all) struct SecurityAudit {
  source_bytes : Int32
  xml_nodes : Int32
  contexts : Int32
  units : Int32
  facts : Int32
} derive(Eq, @debug.Debug)

///|
fn count_xml_nodes(node : XmlNode) -> Int32 {
  let mut count = 1
  for child in node.children {
    count += count_xml_nodes(child)
  }
  count
}

///|
pub fn audit_instance_source(
  source : StringView,
  limits : XbrlLimits,
) -> Result[SecurityAudit, XbrlError] {
  let document = match parse_xml(source, limits) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let instance = match parse_instance(document, limits) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok({
    source_bytes: source.length(),
    xml_nodes: count_xml_nodes(document.root),
    contexts: instance.contexts.length(),
    units: instance.units.length(),
    facts: instance.facts.length(),
  })
}

///|
pub extend SecurityAudit with Eq::{not_equal, equal}

///|
pub extend SecurityAudit with @debug.Debug::{to_repr}
