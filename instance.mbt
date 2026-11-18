///|
const XBRL_INSTANCE_NS : String = "http://www.xbrl.org/2003/instance"

///|
const XBRL_XLINK_NS : String = "http://www.w3.org/1999/xlink"

///|
const XBRL_LINK_NS : String = "http://www.xbrl.org/2003/linkbase"

///|
const XSD_INSTANCE_NS : String = "http://www.w3.org/2001/XMLSchema-instance"

///|
pub(all) enum XbrlPeriod {
  Instant(String)
  Duration(String, String)
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlContext {
  id : String
  entity_scheme : String
  entity_identifier : String
  period : XbrlPeriod
  segment : XmlNode?
  scenario : XmlNode?
  dimensions : Array[DimensionMember]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) enum XbrlUnit {
  Simple(QName)
  Divide(Array[QName], Array[QName])
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlUnitDefinition {
  id : String
  unit : XbrlUnit
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlFact {
  id : String?
  concept : QName
  context_ref : String
  unit_ref : String?
  decimals : String?
  precision : String?
  language : String?
  value : String
  nil : Bool
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlInstance {
  schema_refs : Array[String]
  contexts : Array[XbrlContext]
  units : Array[XbrlUnitDefinition]
  facts : Array[XbrlFact]
} derive(Eq, @debug.Debug)

///|
pub fn XbrlInstance::context(self : XbrlInstance, id : String) -> XbrlContext? {
  for context in self.contexts {
    if context.id == id {
      return Some(context)
    }
  }
  None
}

///|
pub fn XbrlInstance::unit(
  self : XbrlInstance,
  id : String,
) -> XbrlUnitDefinition? {
  for unit in self.units {
    if unit.id == id {
      return Some(unit)
    }
  }
  None
}

///|
pub fn XbrlInstance::facts_for_context(
  self : XbrlInstance,
  id : String,
) -> Array[XbrlFact] {
  let result : Array[XbrlFact] = []
  for fact in self.facts {
    if fact.context_ref == id {
      result.push(fact)
    }
  }
  result
}

///|
pub fn XbrlInstance::facts_for_concept(
  self : XbrlInstance,
  concept : QName,
) -> Array[XbrlFact] {
  let result : Array[XbrlFact] = []
  for fact in self.facts {
    if fact.concept == concept {
      result.push(fact)
    }
  }
  result
}

///|
fn is_ascii_digit(code : UInt16) -> Bool {
  code >= 48 && code <= 57
}

///|
fn parse_date_number(value : StringView, start : Int32, end : Int32) -> Int32 {
  let mut result = 0
  let mut index = start
  while index < end {
    result = result * 10 + value.at(index).to_int() - 48
    index += 1
  }
  result
}

///|
fn is_leap_year(year : Int32) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
fn days_in_month(year : Int32, month : Int32) -> Int32 {
  if month == 2 {
    if is_leap_year(year) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
fn has_valid_timezone(value : StringView, start : Int32) -> Bool {
  let remaining = value.length() - start
  if remaining == 0 {
    return true
  }
  if remaining == 1 {
    return value.at(start) == 90
  }
  if remaining != 6 {
    return false
  }
  if value.at(start) != 43 && value.at(start) != 45 {
    return false
  }
  if value.at(start + 3) != 58 {
    return false
  }
  if !is_ascii_digit(value.at(start + 1)) ||
    !is_ascii_digit(value.at(start + 2)) ||
    !is_ascii_digit(value.at(start + 4)) ||
    !is_ascii_digit(value.at(start + 5)) {
    return false
  }
  let hour = parse_date_number(value, start + 1, start + 3)
  let minute = parse_date_number(value, start + 4, start + 6)
  minute <= 59 && (hour < 14 || (hour == 14 && minute == 0))
}

///|
fn is_valid_xbrl_date(value : StringView) -> Bool {
  let text = value.trim()
  if text.length() < 10 {
    return false
  }
  let mut index = 0
  while index < 10 {
    if index == 4 || index == 7 {
      if text.at(index) != 45 {
        return false
      }
    } else if !is_ascii_digit(text.at(index)) {
      return false
    }
    index += 1
  }
  let year = parse_date_number(text, 0, 4)
  let month = parse_date_number(text, 5, 7)
  let day = parse_date_number(text, 8, 10)
  if year == 0 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > days_in_month(year, month) {
    return false
  }
  has_valid_timezone(text, 10)
}

///|
fn required_unqualified_attribute(node : XmlNode, name : String) -> String? {
  node.attribute("", name)
}

///|
fn parse_identifier(entity : XmlNode) -> Result[(String, String), XbrlError] {
  let identifier = match entity.child(XBRL_INSTANCE_NS, "identifier") {
    Some(value) => value
    None =>
      return Err(InvalidContext("entity identifier is required", entity.offset))
  }
  let scheme = match required_unqualified_attribute(identifier, "scheme") {
    Some(value) if value.trim().length() > 0 => value.trim().to_owned()
    _ =>
      return Err(
        InvalidContext(
          "entity identifier scheme is required",
          identifier.offset,
        ),
      )
  }
  let text = identifier.text.trim().to_owned()
  if text == "" {
    return Err(
      InvalidContext("entity identifier value is empty", identifier.offset),
    )
  }
  Ok((scheme, text))
}

///|
fn parse_period(period : XmlNode) -> Result[XbrlPeriod, XbrlError] {
  let instant = period.child(XBRL_INSTANCE_NS, "instant")
  let start = period.child(XBRL_INSTANCE_NS, "startDate")
  let end = period.child(XBRL_INSTANCE_NS, "endDate")
  match instant {
    Some(node) => {
      if start is Some(_) || end is Some(_) {
        return Err(
          InvalidContext(
            "period cannot mix instant and duration dates",
            period.offset,
          ),
        )
      }
      let value = node.text.trim().to_owned()
      if !is_valid_xbrl_date(value) {
        return Err(InvalidContext("invalid instant date", node.offset))
      }
      Ok(Instant(value))
    }
    None => {
      let start_node = match start {
        Some(value) => value
        None =>
          return Err(
            InvalidContext(
              "period requires instant or startDate/endDate",
              period.offset,
            ),
          )
      }
      let end_node = match end {
        Some(value) => value
        None =>
          return Err(
            InvalidContext("period startDate requires endDate", period.offset),
          )
      }
      let start_value = start_node.text.trim().to_owned()
      let end_value = end_node.text.trim().to_owned()
      if !is_valid_xbrl_date(start_value) {
        return Err(InvalidContext("invalid startDate", start_node.offset))
      }
      if !is_valid_xbrl_date(end_value) {
        return Err(InvalidContext("invalid endDate", end_node.offset))
      }
      if start_value > end_value {
        return Err(
          InvalidContext("period startDate is after endDate", period.offset),
        )
      }
      Ok(Duration(start_value, end_value))
    }
  }
}

///|
fn parse_context(node : XmlNode) -> Result[XbrlContext, XbrlError] {
  let id = match required_unqualified_attribute(node, "id") {
    Some(value) if value.trim().length() > 0 => value.trim().to_owned()
    _ => return Err(InvalidContext("context id is required", node.offset))
  }
  let entity = match node.child(XBRL_INSTANCE_NS, "entity") {
    Some(value) => value
    None =>
      return Err(InvalidContext("context entity is required", node.offset))
  }
  let (entity_scheme, entity_identifier) = match parse_identifier(entity) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let period_node = match node.child(XBRL_INSTANCE_NS, "period") {
    Some(value) => value
    None =>
      return Err(InvalidContext("context period is required", node.offset))
  }
  let period = match parse_period(period_node) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let segment = entity.child(XBRL_INSTANCE_NS, "segment")
  let scenario = node.child(XBRL_INSTANCE_NS, "scenario")
  let dimensions = match parse_context_dimensions(segment, scenario) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok({
    id,
    entity_scheme,
    entity_identifier,
    period,
    segment,
    scenario,
    dimensions,
    offset: node.offset,
  })
}

///|
fn parse_measure(node : XmlNode) -> Result[QName, XbrlError] {
  let lexical = node.text.trim()
  if lexical.length() == 0 {
    return Err(InvalidUnit("unit measure is empty", node.offset))
  }
  resolve_qname(lexical, node.namespaces, true)
}

///|
fn parse_unit_measures(
  parent : XmlNode,
  local_name : String,
) -> Result[Array[QName], XbrlError] {
  let container = match parent.child(XBRL_INSTANCE_NS, local_name) {
    Some(value) => value
    None => return Err(InvalidUnit("missing " + local_name, parent.offset))
  }
  let measures = container.children_named(XBRL_INSTANCE_NS, "measure")
  if measures.length() == 0 {
    return Err(
      InvalidUnit(
        local_name + " requires at least one measure",
        container.offset,
      ),
    )
  }
  let result : Array[QName] = []
  for measure in measures {
    let parsed = match parse_measure(measure) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    result.push(parsed)
  }
  Ok(result)
}

///|
fn parse_unit(node : XmlNode) -> Result[XbrlUnitDefinition, XbrlError] {
  let id = match required_unqualified_attribute(node, "id") {
    Some(value) if value.trim().length() > 0 => value.trim().to_owned()
    _ => return Err(InvalidUnit("unit id is required", node.offset))
  }
  let divide = node.child(XBRL_INSTANCE_NS, "divide")
  let measures = node.children_named(XBRL_INSTANCE_NS, "measure")
  match divide {
    Some(value) => {
      if measures.length() > 0 {
        return Err(
          InvalidUnit("unit cannot mix simple and divide measures", node.offset),
        )
      }
      let numerator = match parse_unit_measures(value, "unitNumerator") {
        Ok(result) => result
        Err(err) => return Err(err)
      }
      let denominator = match parse_unit_measures(value, "unitDenominator") {
        Ok(result) => result
        Err(err) => return Err(err)
      }
      Ok({ id, unit: Divide(numerator, denominator), offset: node.offset, })
    }
    None => {
      if measures.length() != 1 {
        return Err(
          InvalidUnit("simple unit requires exactly one measure", node.offset),
        )
      }
      let measure = match parse_measure(measures[0]) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok({ id, unit: Simple(measure), offset: node.offset, })
    }
  }
}

///|
fn parse_boolean(
  value : StringView,
  offset : Int32,
  feature : String,
) -> Result[Bool, XbrlError] {
  let text = value.trim()
  if text == "true" || text == "1" {
    Ok(true)
  } else if text == "false" || text == "0" {
    Ok(false)
  } else {
    Err(InvalidFact(feature + " must be an XML boolean", offset))
  }
}

///|
fn parse_fact(node : XmlNode) -> Result[XbrlFact, XbrlError] {
  let context_ref = match required_unqualified_attribute(node, "contextRef") {
    Some(value) if value.trim().length() > 0 => value.trim().to_owned()
    _ => return Err(InvalidFact("fact contextRef is required", node.offset))
  }
  if node.children.length() > 0 {
    return Err(UnsupportedFeature("tuple facts are not supported"))
  }
  let nil = match node.attribute(XSD_INSTANCE_NS, "nil") {
    Some(value) =>
      match parse_boolean(value, node.offset, "xsi:nil") {
        Ok(result) => result
        Err(err) => return Err(err)
      }
    None => false
  }
  if nil && node.text.trim().length() > 0 {
    return Err(InvalidFact("nil fact must not contain text", node.offset))
  }
  Ok({
    id: node.attribute("", "id"),
    concept: node.name,
    context_ref,
    unit_ref: required_unqualified_attribute(node, "unitRef"),
    decimals: required_unqualified_attribute(node, "decimals"),
    precision: required_unqualified_attribute(node, "precision"),
    language: node.attribute("http://www.w3.org/XML/1998/namespace", "lang"),
    value: node.text,
    nil,
    offset: node.offset,
  })
}

///|
fn has_fact_id(facts : Array[XbrlFact], id : String) -> Bool {
  for fact in facts {
    match fact.id {
      Some(existing) if existing == id => return true
      _ => ()
    }
  }
  false
}

///|
pub fn parse_instance(
  document : XmlDocument,
  limits : XbrlLimits,
) -> Result[XbrlInstance, XbrlError] {
  if !document.root.name.matches(XBRL_INSTANCE_NS, "xbrl") {
    return Err(
      InvalidFact("root element must be xbrli:xbrl", document.root.offset),
    )
  }
  let schema_refs : Array[String] = []
  let contexts : Array[XbrlContext] = []
  let units : Array[XbrlUnitDefinition] = []
  let fact_nodes : Array[XmlNode] = []
  for child in document.root.children {
    if child.name.matches(XBRL_LINK_NS, "schemaRef") {
      let href = match child.attribute(XBRL_XLINK_NS, "href") {
        Some(value) if value.trim().length() > 0 => value.trim().to_owned()
        _ =>
          return Err(
            InvalidTaxonomy("schemaRef xlink:href is required", child.offset),
          )
      }
      schema_refs.push(href)
    } else if child.name.namespace_uri == XBRL_INSTANCE_NS {
      if child.name.local_name == "context" {
        let context = match parse_context(child) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for existing in contexts {
          if existing.id == context.id {
            return Err(
              InvalidContext(
                "duplicate context id '" + context.id + "'",
                child.offset,
              ),
            )
          }
        }
        contexts.push(context)
      } else if child.name.local_name == "unit" {
        let unit = match parse_unit(child) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for existing in units {
          if existing.id == unit.id {
            return Err(
              InvalidUnit("duplicate unit id '" + unit.id + "'", child.offset),
            )
          }
        }
        units.push(unit)
      } else {
        return Err(
          UnsupportedFeature(
            "unsupported xbrli element '" + child.name.local_name + "'",
          ),
        )
      }
    } else if required_unqualified_attribute(child, "contextRef") is Some(_) {
      fact_nodes.push(child)
    }
  }
  let facts : Array[XbrlFact] = []
  for node in fact_nodes {
    let fact = match parse_fact(node) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    match fact.id {
      Some(id) =>
        if has_fact_id(facts, id) {
          return Err(DuplicateFact(id, node.offset))
        }
      None => ()
    }
    let mut context_found = false
    for context in contexts {
      if context.id == fact.context_ref {
        context_found = true
        break
      }
    }
    if !context_found {
      return Err(UnresolvedReference("context '" + fact.context_ref + "'"))
    }
    match fact.unit_ref {
      Some(unit_id) => {
        let mut unit_found = false
        for unit in units {
          if unit.id == unit_id {
            unit_found = true
            break
          }
        }
        if !unit_found {
          return Err(UnresolvedReference("unit '" + unit_id + "'"))
        }
      }
      None => ()
    }
    facts.push(fact)
    match limits.check_facts(facts.length()) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok({ schema_refs, contexts, units, facts, })
}

///|
pub fn parse_instance_xml(
  source : StringView,
  limits : XbrlLimits,
) -> Result[XbrlInstance, XbrlError] {
  let document = match parse_xml(source, limits) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  parse_instance(document, limits)
}

///|
pub extend XbrlPeriod with Eq::{not_equal, equal}

///|
pub extend XbrlPeriod with @debug.Debug::{to_repr}

///|
pub extend XbrlContext with Eq::{not_equal, equal}

///|
pub extend XbrlContext with @debug.Debug::{to_repr}

///|
pub extend XbrlUnit with Eq::{not_equal, equal}

///|
pub extend XbrlUnit with @debug.Debug::{to_repr}

///|
pub extend XbrlUnitDefinition with Eq::{not_equal, equal}

///|
pub extend XbrlUnitDefinition with @debug.Debug::{to_repr}

///|
pub extend XbrlFact with Eq::{not_equal, equal}

///|
pub extend XbrlFact with @debug.Debug::{to_repr}

///|
pub extend XbrlInstance with Eq::{not_equal, equal}

///|
pub extend XbrlInstance with @debug.Debug::{to_repr}
