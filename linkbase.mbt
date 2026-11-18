///|
const XBRL_CONCEPT_LABEL_ARROLE : String = "http://www.xbrl.org/2003/arcrole/concept-label"

///|
const XBRL_PARENT_CHILD_ARROLE : String = "http://www.xbrl.org/2003/arcrole/parent-child"

///|
const XBRL_SUMMATION_ITEM_ARROLE : String = "http://www.xbrl.org/2003/arcrole/summation-item"

///|
const XML_LANGUAGE_NS : String = "http://www.w3.org/XML/1998/namespace"

///|
pub(all) enum ArcUse {
  Optional
  Prohibited
  Unspecified
} derive(Eq, @debug.Debug)

///|
pub(all) struct LinkLocator {
  label : String
  href : String
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct LabelResource {
  label : String
  role_uri : String
  language : String?
  text : String
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct LinkArc {
  from_label : String
  to_label : String
  arcrole : String
  order : Decimal?
  weight : Decimal?
  preferred_label : QName?
  arc_use : ArcUse
  priority : Int32
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct LabelLink {
  role_uri : String
  locators : Array[LinkLocator]
  labels : Array[LabelResource]
  arcs : Array[LinkArc]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct PresentationLink {
  role_uri : String
  locators : Array[LinkLocator]
  arcs : Array[LinkArc]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct CalculationLink {
  role_uri : String
  locators : Array[LinkLocator]
  arcs : Array[LinkArc]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XbrlLinkbase {
  label_links : Array[LabelLink]
  presentation_links : Array[PresentationLink]
  calculation_links : Array[CalculationLink]
} derive(Eq, @debug.Debug)

///|
pub(all) struct ConceptLabel {
  concept : QName
  link_role_uri : String
  label_role_uri : String
  language : String?
  text : String
  priority : Int32
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct PresentationRelation {
  link_role_uri : String
  parent : QName
  child : QName
  order : Decimal?
  preferred_label : QName?
  priority : Int32
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct CalculationRelation {
  link_role_uri : String
  parent : QName
  child : QName
  weight : Decimal
  order : Decimal?
  priority : Int32
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct CalculationGroup {
  role_uri : String
  parent : QName
  relations : Array[CalculationRelation]
} derive(Eq, @debug.Debug)

///|
fn link_xlink_attribute(node : XmlNode, name : String) -> String? {
  match node.attribute(XBRL_XLINK_NS, name) {
    Some(value) if value.trim().length() > 0 => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn required_link_xlink_attribute(
  node : XmlNode,
  name : String,
) -> Result[String, XbrlError] {
  match link_xlink_attribute(node, name) {
    Some(value) => Ok(value)
    None => Err(InvalidLinkbase("xlink:" + name + " is required", node.offset))
  }
}

///|
fn optional_link_attribute(node : XmlNode, name : String) -> String? {
  match node.attribute("", name) {
    Some(value) if value.trim().length() > 0 => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn check_link_xlink_type(
  node : XmlNode,
  expected : String,
) -> Result[Unit, XbrlError] {
  match link_xlink_attribute(node, "type") {
    Some(value) =>
      if value == expected {
        Ok(())
      } else {
        Err(
          InvalidLinkbase(
            "expected xlink:type='" + expected + "', found '" + value + "'",
            node.offset,
          ),
        )
      }
    None => Ok(())
  }
}

///|
fn parse_priority(
  value : StringView,
  offset : Int32,
) -> Result[Int32, XbrlError] {
  let text = value.trim()
  if text.length() == 0 {
    return Err(InvalidLinkbase("arc priority is empty", offset))
  }
  let mut result : Int32 = 0
  let mut index = 0
  while index < text.length() {
    let code = text.at(index)
    if code < 48 || code > 57 {
      return Err(
        InvalidLinkbase("arc priority must be a non-negative integer", offset),
      )
    }
    if result > (2_147_483_647 - (code.to_int() - 48)) / 10 {
      return Err(InvalidLinkbase("arc priority is too large", offset))
    }
    result = result * 10 + code.to_int() - 48
    index += 1
  }
  Ok(result)
}

///|
fn parse_arc_use(node : XmlNode) -> Result[ArcUse, XbrlError] {
  match link_xlink_attribute(node, "use") {
    Some("optional") => Ok(Optional)
    Some("prohibited") => Ok(Prohibited)
    Some(value) =>
      Err(InvalidLinkbase("invalid xlink:use '" + value + "'", node.offset))
    None => Ok(Unspecified)
  }
}

///|
fn parse_locator(node : XmlNode) -> Result[LinkLocator, XbrlError] {
  match check_link_xlink_type(node, "locator") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let label = match required_link_xlink_attribute(node, "label") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let href = match required_link_xlink_attribute(node, "href") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok({ label, href, offset: node.offset, })
}

///|
fn parse_label_resource(node : XmlNode) -> Result[LabelResource, XbrlError] {
  match check_link_xlink_type(node, "resource") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let label = match required_link_xlink_attribute(node, "label") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let role_uri = match required_link_xlink_attribute(node, "role") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok({
    label,
    role_uri,
    language: node.attribute(XML_LANGUAGE_NS, "lang"),
    text: node.text,
    offset: node.offset,
  })
}

///|
fn parse_link_arc(node : XmlNode) -> Result[LinkArc, XbrlError] {
  match check_link_xlink_type(node, "arc") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let from_label = match required_link_xlink_attribute(node, "from") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let to_label = match required_link_xlink_attribute(node, "to") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let arcrole = match required_link_xlink_attribute(node, "arcrole") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let order = match optional_link_attribute(node, "order") {
    Some(value) =>
      match Decimal::parse(value) {
        Ok(decimal) => Some(decimal)
        Err(err) => return Err(err)
      }
    None => None
  }
  let weight = match optional_link_attribute(node, "weight") {
    Some(value) =>
      match Decimal::parse(value) {
        Ok(decimal) => Some(decimal)
        Err(err) => return Err(err)
      }
    None => None
  }
  let preferred_label = match optional_link_attribute(node, "preferredLabel") {
    Some(value) =>
      match resolve_qname(value, node.namespaces, true) {
        Ok(qname) => Some(qname)
        Err(err) => return Err(err)
      }
    None => None
  }
  let priority = match optional_link_attribute(node, "priority") {
    Some(value) =>
      match parse_priority(value, node.offset) {
        Ok(number) => number
        Err(err) => return Err(err)
      }
    None => 0
  }
  let arc_use = match parse_arc_use(node) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok({
    from_label,
    to_label,
    arcrole,
    order,
    weight,
    preferred_label,
    arc_use,
    priority,
    offset: node.offset,
  })
}

///|
fn has_locator_label(locators : Array[LinkLocator], label : String) -> Bool {
  for locator in locators {
    if locator.label == label {
      return true
    }
  }
  false
}

///|
fn has_resource_label(labels : Array[LabelResource], label : String) -> Bool {
  for resource in labels {
    if resource.label == label {
      return true
    }
  }
  false
}

///|
fn locator_by_label(
  locators : Array[LinkLocator],
  label : String,
) -> LinkLocator? {
  for locator in locators {
    if locator.label == label {
      return Some(locator)
    }
  }
  None
}

///|
fn label_resource_by_label(
  labels : Array[LabelResource],
  label : String,
) -> LabelResource? {
  for resource in labels {
    if resource.label == label {
      return Some(resource)
    }
  }
  None
}

///|
fn validate_label_link(link : LabelLink) -> Result[Unit, XbrlError] {
  for arc in link.arcs {
    if arc.arcrole != XBRL_CONCEPT_LABEL_ARROLE {
      return Err(
        InvalidLinkbase(
          "labelArc requires the concept-label arcrole",
          arc.offset,
        ),
      )
    }
    if locator_by_label(link.locators, arc.from_label) is None {
      return Err(
        InvalidLinkbase("labelArc from label does not resolve", arc.offset),
      )
    }
    if label_resource_by_label(link.labels, arc.to_label) is None {
      return Err(
        InvalidLinkbase("labelArc to label does not resolve", arc.offset),
      )
    }
  }
  Ok(())
}

///|
fn validate_presentation_link(
  link : PresentationLink,
) -> Result[Unit, XbrlError] {
  for arc in link.arcs {
    if arc.arcrole != XBRL_PARENT_CHILD_ARROLE {
      return Err(
        InvalidLinkbase(
          "presentationArc requires the parent-child arcrole",
          arc.offset,
        ),
      )
    }
    if locator_by_label(link.locators, arc.from_label) is None ||
      locator_by_label(link.locators, arc.to_label) is None {
      return Err(
        InvalidLinkbase(
          "presentationArc endpoint does not resolve to a locator",
          arc.offset,
        ),
      )
    }
  }
  Ok(())
}

///|
fn parse_label_link(node : XmlNode) -> Result[LabelLink, XbrlError] {
  match check_link_xlink_type(node, "extended") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let role_uri = match required_link_xlink_attribute(node, "role") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let locators : Array[LinkLocator] = []
  let labels : Array[LabelResource] = []
  let arcs : Array[LinkArc] = []
  for child in node.children {
    if child.name.matches(XBRL_LINK_NS, "loc") {
      let locator = match parse_locator(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_locator_label(locators, locator.label) ||
        has_resource_label(labels, locator.label) {
        return Err(
          InvalidLinkbase(
            "duplicate XLink label '" + locator.label + "'",
            child.offset,
          ),
        )
      }
      locators.push(locator)
    } else if child.name.matches(XBRL_LINK_NS, "label") {
      let resource = match parse_label_resource(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_resource_label(labels, resource.label) ||
        has_locator_label(locators, resource.label) {
        return Err(
          InvalidLinkbase(
            "duplicate XLink label '" + resource.label + "'",
            child.offset,
          ),
        )
      }
      labels.push(resource)
    } else if child.name.matches(XBRL_LINK_NS, "labelArc") {
      let arc = match parse_link_arc(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      arcs.push(arc)
    }
  }
  let link = { role_uri, locators, labels, arcs, offset: node.offset, }
  match validate_label_link(link) {
    Ok(_) => Ok(link)
    Err(err) => Err(err)
  }
}

///|
fn parse_presentation_link(
  node : XmlNode,
) -> Result[PresentationLink, XbrlError] {
  match check_link_xlink_type(node, "extended") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let role_uri = match required_link_xlink_attribute(node, "role") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let locators : Array[LinkLocator] = []
  let arcs : Array[LinkArc] = []
  for child in node.children {
    if child.name.matches(XBRL_LINK_NS, "loc") {
      let locator = match parse_locator(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_locator_label(locators, locator.label) {
        return Err(
          InvalidLinkbase(
            "duplicate locator label '" + locator.label + "'",
            child.offset,
          ),
        )
      }
      locators.push(locator)
    } else if child.name.matches(XBRL_LINK_NS, "presentationArc") {
      let arc = match parse_link_arc(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      arcs.push(arc)
    }
  }
  let link : PresentationLink = {
    role_uri,
    locators,
    arcs,
    offset: node.offset,
  }
  match validate_presentation_link(link) {
    Ok(_) => Ok(link)
    Err(err) => Err(err)
  }
}

///|
fn validate_calculation_link(link : CalculationLink) -> Result[Unit, XbrlError] {
  for arc in link.arcs {
    if arc.arcrole != XBRL_SUMMATION_ITEM_ARROLE {
      return Err(
        InvalidLinkbase(
          "calculationArc requires the summation-item arcrole",
          arc.offset,
        ),
      )
    }
    if locator_by_label(link.locators, arc.from_label) is None ||
      locator_by_label(link.locators, arc.to_label) is None {
      return Err(
        InvalidLinkbase(
          "calculationArc endpoint does not resolve to a locator",
          arc.offset,
        ),
      )
    }
    if arc.weight is None {
      return Err(
        InvalidLinkbase("calculationArc weight is required", arc.offset),
      )
    }
  }
  Ok(())
}

///|
fn parse_calculation_link(node : XmlNode) -> Result[CalculationLink, XbrlError] {
  match check_link_xlink_type(node, "extended") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let role_uri = match required_link_xlink_attribute(node, "role") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let locators : Array[LinkLocator] = []
  let arcs : Array[LinkArc] = []
  for child in node.children {
    if child.name.matches(XBRL_LINK_NS, "loc") {
      let locator = match parse_locator(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_locator_label(locators, locator.label) {
        return Err(
          InvalidLinkbase(
            "duplicate locator label '" + locator.label + "'",
            child.offset,
          ),
        )
      }
      locators.push(locator)
    } else if child.name.matches(XBRL_LINK_NS, "calculationArc") {
      let arc = match parse_link_arc(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      arcs.push(arc)
    }
  }
  let link : CalculationLink = {
    role_uri,
    locators,
    arcs,
    offset: node.offset,
  }
  match validate_calculation_link(link) {
    Ok(_) => Ok(link)
    Err(err) => Err(err)
  }
}

///|
pub fn parse_linkbase(
  document : XmlDocument,
  limits : XbrlLimits,
) -> Result[XbrlLinkbase, XbrlError] {
  if !document.root.name.matches(XBRL_LINK_NS, "linkbase") {
    return Err(
      InvalidLinkbase(
        "root element must be link:linkbase",
        document.root.offset,
      ),
    )
  }
  let label_links : Array[LabelLink] = []
  let presentation_links : Array[PresentationLink] = []
  let calculation_links : Array[CalculationLink] = []
  let mut total_arcs = 0
  for child in document.root.children {
    if child.name.matches(XBRL_LINK_NS, "labelLink") {
      let link = match parse_label_link(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      total_arcs += link.arcs.length()
      match limits.check_linkbase_arcs(total_arcs) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      label_links.push(link)
    } else if child.name.matches(XBRL_LINK_NS, "presentationLink") {
      let link = match parse_presentation_link(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      total_arcs += link.arcs.length()
      match limits.check_linkbase_arcs(total_arcs) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      presentation_links.push(link)
    } else if child.name.matches(XBRL_LINK_NS, "calculationLink") {
      let link = match parse_calculation_link(child) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      total_arcs += link.arcs.length()
      match limits.check_linkbase_arcs(total_arcs) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      calculation_links.push(link)
    }
  }
  Ok({ label_links, presentation_links, calculation_links, })
}

///|
pub fn parse_linkbase_xml(
  source : StringView,
  limits : XbrlLimits,
) -> Result[XbrlLinkbase, XbrlError] {
  let document = match parse_xml(source, limits) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  parse_linkbase(document, limits)
}

///|
fn href_fragment(
  href : StringView,
  offset : Int32,
) -> Result[String, XbrlError] {
  let mut hash : Int32 = -1
  let mut index = 0
  while index < href.length() {
    if href.at(index) == 35 {
      hash = index
    }
    index += 1
  }
  if hash < 0 || hash + 1 >= href.length() {
    return Err(
      InvalidLinkbase("locator href requires a fragment identifier", offset),
    )
  }
  Ok(href.view(start_offset=hash + 1).to_owned())
}

///|
fn concept_by_id(taxonomy : ResolvedTaxonomy, id : String) -> XbrlConcept? {
  for schema in taxonomy.schemas {
    for concept in schema.schema.concepts {
      match concept.id {
        Some(existing) if existing == id => return Some(concept)
        _ => ()
      }
    }
  }
  None
}

///|
fn locator_concept(
  taxonomy : ResolvedTaxonomy,
  locator : LinkLocator,
) -> Result[XbrlConcept, XbrlError] {
  let id = match href_fragment(locator.href, locator.offset) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match concept_by_id(taxonomy, id) {
    Some(concept) => Ok(concept)
    None => Err(UnresolvedReference("concept id '" + id + "'"))
  }
}

///|
pub fn XbrlLinkbase::labels(
  self : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
) -> Result[Array[ConceptLabel], XbrlError] {
  let result : Array[ConceptLabel] = []
  for link in self.label_links {
    for locator in link.locators {
      let concept = match locator_concept(taxonomy, locator) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      for arc in link.arcs {
        if arc.from_label == locator.label && arc.arc_use != Prohibited {
          let resource = match
            label_resource_by_label(link.labels, arc.to_label) {
            Some(value) => value
            None =>
              return Err(
                InvalidLinkbase("labelArc target does not resolve", arc.offset),
              )
          }
          result.push({
            concept: concept.name,
            link_role_uri: link.role_uri,
            label_role_uri: resource.role_uri,
            language: resource.language,
            text: resource.text,
            priority: arc.priority,
            offset: resource.offset,
          })
        }
      }
    }
  }
  Ok(result)
}

///|
pub fn XbrlLinkbase::calculation_relations(
  self : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
) -> Result[Array[CalculationRelation], XbrlError] {
  let result : Array[CalculationRelation] = []
  for link in self.calculation_links {
    for arc in link.arcs {
      if arc.arc_use == Prohibited {
        continue
      }
      let from_locator = match locator_by_label(link.locators, arc.from_label) {
        Some(value) => value
        None =>
          return Err(
            InvalidLinkbase(
              "calculationArc from label does not resolve",
              arc.offset,
            ),
          )
      }
      let to_locator = match locator_by_label(link.locators, arc.to_label) {
        Some(value) => value
        None =>
          return Err(
            InvalidLinkbase(
              "calculationArc to label does not resolve",
              arc.offset,
            ),
          )
      }
      let parent = match locator_concept(taxonomy, from_locator) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let child = match locator_concept(taxonomy, to_locator) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let weight = match arc.weight {
        Some(value) => value
        None =>
          return Err(
            InvalidLinkbase("calculationArc weight is required", arc.offset),
          )
      }
      result.push({
        link_role_uri: link.role_uri,
        parent: parent.name,
        child: child.name,
        weight,
        order: arc.order,
        priority: arc.priority,
        offset: arc.offset,
      })
    }
  }
  Ok(result)
}

///|
pub fn XbrlLinkbase::calculation_groups(
  self : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
) -> Result[Array[CalculationGroup], XbrlError] {
  let relations = match self.calculation_relations(taxonomy) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let groups : Array[CalculationGroup] = []
  for relation in relations {
    let mut found = false
    for group in groups {
      if group.role_uri == relation.link_role_uri &&
        group.parent == relation.parent {
        group.relations.push(relation)
        found = true
        break
      }
    }
    if !found {
      groups.push({
        role_uri: relation.link_role_uri,
        parent: relation.parent,
        relations: [relation],
      })
    }
  }
  Ok(groups)
}

///|
pub fn XbrlLinkbase::presentation_relations(
  self : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
) -> Result[Array[PresentationRelation], XbrlError] {
  let result : Array[PresentationRelation] = []
  for link in self.presentation_links {
    for arc in link.arcs {
      if arc.arc_use != Prohibited {
        let from_locator = match
          locator_by_label(link.locators, arc.from_label) {
          Some(value) => value
          None =>
            return Err(
              InvalidLinkbase(
                "presentationArc from label does not resolve",
                arc.offset,
              ),
            )
        }
        let to_locator = match locator_by_label(link.locators, arc.to_label) {
          Some(value) => value
          None =>
            return Err(
              InvalidLinkbase(
                "presentationArc to label does not resolve",
                arc.offset,
              ),
            )
        }
        let parent = match locator_concept(taxonomy, from_locator) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let child = match locator_concept(taxonomy, to_locator) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        result.push({
          link_role_uri: link.role_uri,
          parent: parent.name,
          child: child.name,
          order: arc.order,
          preferred_label: arc.preferred_label,
          priority: arc.priority,
          offset: arc.offset,
        })
      }
    }
  }
  Ok(result)
}

///|
pub extend ArcUse with Eq::{not_equal, equal}

///|
pub extend ArcUse with @debug.Debug::{to_repr}

///|
pub extend LinkLocator with Eq::{not_equal, equal}

///|
pub extend LinkLocator with @debug.Debug::{to_repr}

///|
pub extend LabelResource with Eq::{not_equal, equal}

///|
pub extend LabelResource with @debug.Debug::{to_repr}

///|
pub extend LinkArc with Eq::{not_equal, equal}

///|
pub extend LinkArc with @debug.Debug::{to_repr}

///|
pub extend LabelLink with Eq::{not_equal, equal}

///|
pub extend LabelLink with @debug.Debug::{to_repr}

///|
pub extend CalculationLink with Eq::{not_equal, equal}

///|
pub extend CalculationLink with @debug.Debug::{to_repr}

///|
pub extend PresentationLink with Eq::{not_equal, equal}

///|
pub extend PresentationLink with @debug.Debug::{to_repr}

///|
pub extend XbrlLinkbase with Eq::{not_equal, equal}

///|
pub extend XbrlLinkbase with @debug.Debug::{to_repr}

///|
pub extend ConceptLabel with Eq::{not_equal, equal}

///|
pub extend ConceptLabel with @debug.Debug::{to_repr}

///|
pub extend PresentationRelation with Eq::{not_equal, equal}

///|
pub extend PresentationRelation with @debug.Debug::{to_repr}

///|
pub extend CalculationRelation with Eq::{not_equal, equal}

///|
pub extend CalculationRelation with @debug.Debug::{to_repr}

///|
pub extend CalculationGroup with Eq::{not_equal, equal}

///|
pub extend CalculationGroup with @debug.Debug::{to_repr}
