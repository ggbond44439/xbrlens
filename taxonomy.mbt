///|
const XSD_NS : String = "http://www.w3.org/2001/XMLSchema"

///|
pub(all) enum ConceptKind {
  Item
  Tuple
} derive(Eq, @debug.Debug)

///|
pub(all) enum ConceptPeriodType {
  Instant
  Duration
  Unspecified
} derive(Eq, @debug.Debug)

///|
pub(all) enum ConceptBalance {
  Debit
  Credit
  Unspecified
} derive(Eq, @debug.Debug)

///|
pub(all) struct TaxonomyImport {
  namespace_uri : String
  schema_location : String?
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlConcept {
  name : QName
  id : String?
  type_name : QName
  substitution_group : QName
  kind : ConceptKind
  period_type : ConceptPeriodType
  balance : ConceptBalance
  is_abstract : Bool
  nillable : Bool
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct RoleType {
  id : String
  role_uri : String
  definition : String?
  used_on : Array[QName]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlSchema {
  target_namespace : String
  imports : Array[TaxonomyImport]
  concepts : Array[XbrlConcept]
  role_types : Array[RoleType]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub fn XbrlSchema::concept(
  self : XbrlSchema,
  namespace_uri : String,
  local_name : String,
) -> XbrlConcept? {
  for concept in self.concepts {
    if concept.name.matches(namespace_uri, local_name) {
      return Some(concept)
    }
  }
  None
}

///|
fn taxonomy_boolean(
  value : StringView,
  offset : Int32,
  field : String,
) -> Result[Bool, XbrlError] {
  let text = value.trim()
  if text == "true" || text == "1" {
    Ok(true)
  } else if text == "false" || text == "0" {
    Ok(false)
  } else {
    Err(InvalidTaxonomy(field + " must be an XML boolean", offset))
  }
}

///|
fn optional_taxonomy_attribute(node : XmlNode, name : String) -> String? {
  match node.attribute("", name) {
    Some(value) if value.trim().length() > 0 => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn parse_optional_qname_attribute(
  node : XmlNode,
  name : String,
) -> Result[QName?, XbrlError] {
  match node.attribute("", name) {
    Some(value) =>
      if value.trim().length() == 0 {
        Err(InvalidTaxonomy(name + " cannot be empty", node.offset))
      } else {
        match resolve_qname(value.trim(), node.namespaces, true) {
          Ok(qname) => Ok(Some(qname))
          Err(err) => Err(err)
        }
      }
    None => Ok(None)
  }
}

///|
fn required_qname_attribute(
  node : XmlNode,
  name : String,
) -> Result[QName, XbrlError] {
  match parse_optional_qname_attribute(node, name) {
    Ok(Some(value)) => Ok(value)
    Ok(None) => Err(InvalidTaxonomy(name + " is required", node.offset))
    Err(err) => Err(err)
  }
}

///|
fn parse_concept_period_type(
  node : XmlNode,
) -> Result[ConceptPeriodType, XbrlError] {
  match optional_taxonomy_attribute(node, "periodType") {
    Some("instant") => Ok(Instant)
    Some("duration") => Ok(Duration)
    Some(_) =>
      Err(
        InvalidTaxonomy("periodType must be instant or duration", node.offset),
      )
    None => Ok(Unspecified)
  }
}

///|
fn parse_concept_balance(node : XmlNode) -> Result[ConceptBalance, XbrlError] {
  match optional_taxonomy_attribute(node, "balance") {
    Some("debit") => Ok(Debit)
    Some("credit") => Ok(Credit)
    Some(_) =>
      Err(InvalidTaxonomy("balance must be debit or credit", node.offset))
    None => Ok(Unspecified)
  }
}

///|
fn parse_optional_boolean_attribute(
  node : XmlNode,
  name : String,
) -> Result[Bool, XbrlError] {
  match node.attribute("", name) {
    Some(value) => taxonomy_boolean(value, node.offset, name)
    None => Ok(false)
  }
}

///|
fn parse_concept(
  node : XmlNode,
  target_namespace : String,
) -> Result[XbrlConcept?, XbrlError] {
  let local_name = match optional_taxonomy_attribute(node, "name") {
    Some(value) => value
    None => return Err(InvalidTaxonomy("concept name is required", node.offset))
  }
  let substitution_group = match
    parse_optional_qname_attribute(node, "substitutionGroup") {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(err) => return Err(err)
  }
  let kind = if substitution_group.matches(XBRL_INSTANCE_NS, "item") {
    Item
  } else if substitution_group.matches(XBRL_INSTANCE_NS, "tuple") {
    Tuple
  } else {
    return Ok(None)
  }
  let type_name = match required_qname_attribute(node, "type") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let period_type = match parse_concept_period_type(node) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let balance = match parse_concept_balance(node) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let is_abstract = match parse_optional_boolean_attribute(node, "abstract") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let nillable = match parse_optional_boolean_attribute(node, "nillable") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let name = match QName::new(target_namespace, local_name) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(
    Some({
      name,
      id: optional_taxonomy_attribute(node, "id"),
      type_name,
      substitution_group,
      kind,
      period_type,
      balance,
      is_abstract,
      nillable,
      offset: node.offset,
    }),
  )
}

///|
fn parse_taxonomy_import(node : XmlNode) -> Result[TaxonomyImport, XbrlError] {
  let namespace_uri = match optional_taxonomy_attribute(node, "namespace") {
    Some(value) => value
    None =>
      return Err(InvalidTaxonomy("import namespace is required", node.offset))
  }
  Ok({
    namespace_uri,
    schema_location: optional_taxonomy_attribute(node, "schemaLocation"),
    offset: node.offset,
  })
}

///|
fn parse_role_type(node : XmlNode) -> Result[RoleType, XbrlError] {
  let id = match optional_taxonomy_attribute(node, "id") {
    Some(value) => value
    None => return Err(InvalidTaxonomy("roleType id is required", node.offset))
  }
  let role_uri = match optional_taxonomy_attribute(node, "roleURI") {
    Some(value) => value
    None =>
      return Err(InvalidTaxonomy("roleType roleURI is required", node.offset))
  }
  let definition = match node.child(XBRL_LINK_NS, "definition") {
    Some(value) => {
      let text = value.text.trim().to_owned()
      if text == "" {
        None
      } else {
        Some(text)
      }
    }
    None => None
  }
  let used_on : Array[QName] = []
  for used in node.children_named(XBRL_LINK_NS, "usedOn") {
    let text = used.text.trim()
    if text.length() == 0 {
      return Err(InvalidTaxonomy("usedOn QName is empty", used.offset))
    }
    let qname = match resolve_qname(text, used.namespaces, true) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    used_on.push(qname)
  }
  Ok({ id, role_uri, definition, used_on, offset: node.offset, })
}

///|
fn has_concept_name(concepts : Array[XbrlConcept], name : QName) -> Bool {
  for concept in concepts {
    if concept.name == name {
      return true
    }
  }
  false
}

///|
fn has_role_id(roles : Array[RoleType], id : String) -> Bool {
  for role in roles {
    if role.id == id {
      return true
    }
  }
  false
}

///|
pub fn parse_taxonomy(document : XmlDocument) -> Result[XbrlSchema, XbrlError] {
  if !document.root.name.matches(XSD_NS, "schema") {
    return Err(
      InvalidTaxonomy("root element must be xs:schema", document.root.offset),
    )
  }
  let target_namespace = match
    optional_taxonomy_attribute(document.root, "targetNamespace") {
    Some(value) => value
    None =>
      return Err(
        InvalidTaxonomy("targetNamespace is required", document.root.offset),
      )
  }
  let imports : Array[TaxonomyImport] = []
  let concepts : Array[XbrlConcept] = []
  let role_types : Array[RoleType] = []
  for child in document.root.children {
    if child.name.matches(XSD_NS, "import") {
      let imported = match parse_taxonomy_import(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      imports.push(imported)
    } else if child.name.matches(XSD_NS, "element") {
      let concept = match parse_concept(child, target_namespace) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match concept {
        Some(value) => {
          if has_concept_name(concepts, value.name) {
            return Err(
              InvalidTaxonomy(
                "duplicate concept '" + value.name.expanded() + "'",
                value.offset,
              ),
            )
          }
          concepts.push(value)
        }
        None => ()
      }
    } else if child.name.matches(XBRL_LINK_NS, "roleType") {
      let role = match parse_role_type(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_role_id(role_types, role.id) {
        return Err(
          InvalidTaxonomy(
            "duplicate roleType id '" + role.id + "'",
            role.offset,
          ),
        )
      }
      role_types.push(role)
    }
  }
  Ok({
    target_namespace,
    imports,
    concepts,
    role_types,
    offset: document.root.offset,
  })
}

///|
pub fn parse_taxonomy_xml(
  source : StringView,
  limits : XbrlLimits,
) -> Result[XbrlSchema, XbrlError] {
  let document = match parse_xml(source, limits) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  parse_taxonomy(document)
}

///|
pub extend ConceptKind with Eq::{not_equal, equal}

///|
pub extend ConceptKind with @debug.Debug::{to_repr}

///|
pub extend ConceptPeriodType with Eq::{not_equal, equal}

///|
pub extend ConceptPeriodType with @debug.Debug::{to_repr}

///|
pub extend ConceptBalance with Eq::{not_equal, equal}

///|
pub extend ConceptBalance with @debug.Debug::{to_repr}

///|
pub extend TaxonomyImport with Eq::{not_equal, equal}

///|
pub extend TaxonomyImport with @debug.Debug::{to_repr}

///|
pub extend XbrlConcept with Eq::{not_equal, equal}

///|
pub extend XbrlConcept with @debug.Debug::{to_repr}

///|
pub extend RoleType with Eq::{not_equal, equal}

///|
pub extend RoleType with @debug.Debug::{to_repr}

///|
pub extend XbrlSchema with Eq::{not_equal, equal}

///|
pub extend XbrlSchema with @debug.Debug::{to_repr}
