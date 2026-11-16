///|
pub(all) struct XbrlLimits {
  max_source_bytes : Int32
  max_xml_depth : Int32
  max_xml_nodes : Int32
  max_attributes_per_element : Int32
  max_text_bytes : Int32
  max_facts : Int32
  max_taxonomy_documents : Int32
  max_linkbase_arcs : Int32
} derive(Eq, @debug.Debug)

///|
pub fn XbrlLimits::default() -> XbrlLimits {
  {
    max_source_bytes: 8_388_608,
    max_xml_depth: 128,
    max_xml_nodes: 200_000,
    max_attributes_per_element: 64,
    max_text_bytes: 2_097_152,
    max_facts: 100_000,
    max_taxonomy_documents: 512,
    max_linkbase_arcs: 100_000,
  }
}

///|
pub fn XbrlLimits::strict() -> XbrlLimits {
  {
    max_source_bytes: 1_048_576,
    max_xml_depth: 64,
    max_xml_nodes: 50_000,
    max_attributes_per_element: 32,
    max_text_bytes: 524_288,
    max_facts: 20_000,
    max_taxonomy_documents: 128,
    max_linkbase_arcs: 20_000,
  }
}

///|
pub fn XbrlLimits::validate(self : XbrlLimits) -> Result[Unit, XbrlError] {
  let checks : Array[(String, Int32)] = [
    ("max_source_bytes", self.max_source_bytes),
    ("max_xml_depth", self.max_xml_depth),
    ("max_xml_nodes", self.max_xml_nodes),
    ("max_attributes_per_element", self.max_attributes_per_element),
    ("max_text_bytes", self.max_text_bytes),
    ("max_facts", self.max_facts),
    ("max_taxonomy_documents", self.max_taxonomy_documents),
    ("max_linkbase_arcs", self.max_linkbase_arcs),
  ]
  for check in checks {
    if check.1 <= 0 {
      return Err(InvalidLimit(check.0, check.1))
    }
  }
  Ok(())
}

///|
pub fn XbrlLimits::check_source(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("source bytes", actual, self.max_source_bytes)
}

///|
pub fn XbrlLimits::check_depth(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("XML depth", actual, self.max_xml_depth)
}

///|
pub fn XbrlLimits::check_nodes(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("XML nodes", actual, self.max_xml_nodes)
}

///|
pub fn XbrlLimits::check_attributes(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("XML attributes", actual, self.max_attributes_per_element)
}

///|
pub fn XbrlLimits::check_text(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("text bytes", actual, self.max_text_bytes)
}

///|
pub fn XbrlLimits::check_facts(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("facts", actual, self.max_facts)
}

///|
pub fn XbrlLimits::check_taxonomy_documents(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("taxonomy documents", actual, self.max_taxonomy_documents)
}

///|
pub fn XbrlLimits::check_linkbase_arcs(
  self : XbrlLimits,
  actual : Int32,
) -> Result[Unit, XbrlError] {
  check_limit("linkbase arcs", actual, self.max_linkbase_arcs)
}

///|
fn check_limit(
  name : String,
  actual : Int32,
  maximum : Int32,
) -> Result[Unit, XbrlError] {
  if actual > maximum {
    Err(LimitExceeded(name, maximum, actual))
  } else {
    Ok(())
  }
}

///|
pub extend XbrlLimits with Eq::{not_equal, equal}

///|
pub extend XbrlLimits with @debug.Debug::{to_repr}
