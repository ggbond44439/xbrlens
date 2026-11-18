///|
const XBRL_DIMENSIONS_NS : String = "http://xbrl.org/2006/xbrldi"

///|
pub(all) enum DimensionMember {
  Explicit(QName, QName)
  Typed(QName, QName, String)
} derive(Eq, @debug.Debug)

///|
pub fn DimensionMember::dimension(self : DimensionMember) -> QName {
  match self {
    Explicit(dimension, _) => dimension
    Typed(dimension, _, _) => dimension
  }
}

///|
fn dimension_has(dimensions : Array[QName], dimension : QName) -> Bool {
  for existing in dimensions {
    if existing == dimension {
      return true
    }
  }
  false
}

///|
fn required_dimension_attribute(node : XmlNode) -> Result[QName, XbrlError] {
  let lexical = match node.attribute("", "dimension") {
    Some(value) if value.trim().length() > 0 => value.trim()
    _ =>
      return Err(
        InvalidDimension("dimension attribute is required", node.offset),
      )
  }
  resolve_qname(lexical, node.namespaces, true)
}

///|
fn parse_dimension_container(
  container : XmlNode?,
  seen : Array[QName],
) -> Result[Array[DimensionMember], XbrlError] {
  let result : Array[DimensionMember] = []
  let node = match container {
    Some(value) => value
    None => return Ok(result)
  }
  for child in node.children {
    if child.name.matches(XBRL_DIMENSIONS_NS, "explicitMember") {
      let dimension = match required_dimension_attribute(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if dimension_has(seen, dimension) {
        return Err(
          InvalidDimension("duplicate explicit dimension", child.offset),
        )
      }
      if child.children.length() > 0 {
        return Err(
          InvalidDimension(
            "explicitMember cannot contain child elements",
            child.offset,
          ),
        )
      }
      let lexical = child.text.trim()
      if lexical.length() == 0 {
        return Err(
          InvalidDimension("explicitMember value is empty", child.offset),
        )
      }
      let dimension_value = match
        resolve_qname(lexical, child.namespaces, true) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      seen.push(dimension)
      result.push(Explicit(dimension, dimension_value))
    } else if child.name.matches(XBRL_DIMENSIONS_NS, "typedMember") {
      let dimension = match required_dimension_attribute(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if dimension_has(seen, dimension) {
        return Err(InvalidDimension("duplicate typed dimension", child.offset))
      }
      if child.children.length() != 1 {
        return Err(
          InvalidDimension(
            "typedMember requires exactly one member element",
            child.offset,
          ),
        )
      }
      let child_member = child.children[0]
      seen.push(dimension)
      result.push(Typed(dimension, child_member.name, child_member.text))
    }
  }
  Ok(result)
}

///|
pub fn parse_context_dimensions(
  segment : XmlNode?,
  scenario : XmlNode?,
) -> Result[Array[DimensionMember], XbrlError] {
  let seen : Array[QName] = []
  let result : Array[DimensionMember] = []
  let segment_members = match parse_dimension_container(segment, seen) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for item in segment_members {
    result.push(item)
  }
  let scenario_members = match parse_dimension_container(scenario, seen) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for item in scenario_members {
    result.push(item)
  }
  Ok(result)
}

///|
pub fn XbrlContext::dimension(
  self : XbrlContext,
  dimension : QName,
) -> DimensionMember? {
  for item in self.dimensions {
    if item.dimension() == dimension {
      return Some(item)
    }
  }
  None
}

///|
pub extend DimensionMember with Eq::{not_equal, equal}

///|
pub extend DimensionMember with @debug.Debug::{to_repr}
