///|
pub(all) struct TaxonomyCatalogEntry {
  location : String
  namespace_uri : String
  source : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct TaxonomyCatalog {
  entries : Array[TaxonomyCatalogEntry]
} derive(Eq, @debug.Debug)

///|
pub(all) struct ResolvedTaxonomySchema {
  location : String
  schema : XbrlSchema
  source : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct ResolvedTaxonomy {
  root_location : String
  schemas : Array[ResolvedTaxonomySchema]
} derive(Eq, @debug.Debug)

///|
pub fn TaxonomyCatalog::new() -> TaxonomyCatalog {
  { entries: [], }
}

///|
pub fn TaxonomyCatalog::add(
  self : TaxonomyCatalog,
  location : String,
  namespace_uri : String,
  source : StringView,
) -> Result[Unit, XbrlError] {
  let normalized_location = location.trim().to_owned()
  let normalized_namespace = namespace_uri.trim().to_owned()
  if normalized_location == "" {
    return Err(InvalidTaxonomy("catalog location is empty", 0))
  }
  if normalized_namespace == "" {
    return Err(InvalidTaxonomy("catalog namespace is empty", 0))
  }
  for entry in self.entries {
    if entry.location == normalized_location {
      return Err(
        InvalidTaxonomy(
          "duplicate catalog location '" + normalized_location + "'",
          0,
        ),
      )
    }
  }
  self.entries.push({
    location: normalized_location,
    namespace_uri: normalized_namespace,
    source: source.to_owned(),
  })
  Ok(())
}

///|
pub fn TaxonomyCatalog::entry(
  self : TaxonomyCatalog,
  location : String,
) -> TaxonomyCatalogEntry? {
  for entry in self.entries {
    if entry.location == location {
      return Some(entry)
    }
  }
  None
}

///|
fn catalog_location_for_namespace(
  catalog : TaxonomyCatalog,
  namespace_uri : String,
) -> Result[String, XbrlError] {
  let mut found : String? = None
  for entry in catalog.entries {
    if entry.namespace_uri == namespace_uri {
      match found {
        Some(existing) if existing != entry.location =>
          return Err(
            UnresolvedReference("ambiguous namespace '" + namespace_uri + "'"),
          )
        Some(_) => ()
        None => found = Some(entry.location)
      }
    }
  }
  match found {
    Some(location) => Ok(location)
    None =>
      Err(
        UnresolvedReference(
          "namespace '" + namespace_uri + "' is not in the offline catalog",
        ),
      )
  }
}

///|
fn contains_location(locations : Array[String], location : String) -> Bool {
  for existing in locations {
    if existing == location {
      return true
    }
  }
  false
}

///|
pub fn ResolvedTaxonomy::schema(
  self : ResolvedTaxonomy,
  location : String,
) -> ResolvedTaxonomySchema? {
  for schema in self.schemas {
    if schema.location == location {
      return Some(schema)
    }
  }
  None
}

///|
pub fn ResolvedTaxonomy::concept(
  self : ResolvedTaxonomy,
  namespace_uri : String,
  local_name : String,
) -> XbrlConcept? {
  for resolved in self.schemas {
    match resolved.schema.concept(namespace_uri, local_name) {
      Some(concept) => return Some(concept)
      None => ()
    }
  }
  None
}

///|
pub fn TaxonomyCatalog::resolve(
  self : TaxonomyCatalog,
  root_location : String,
  limits : XbrlLimits,
) -> Result[ResolvedTaxonomy, XbrlError] {
  match limits.validate() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let root = root_location.trim().to_owned()
  if root == "" {
    return Err(InvalidTaxonomy("root taxonomy location is empty", 0))
  }
  let queue : Array[String] = [root]
  let mut cursor = 0
  let schemas : Array[ResolvedTaxonomySchema] = []
  while cursor < queue.length() {
    let location = queue[cursor]
    cursor += 1
    if contains_location_for_resolved(schemas, location) {
      continue
    }
    let entry = match self.entry(location) {
      Some(value) => value
      None =>
        return Err(UnresolvedReference("taxonomy location '" + location + "'"))
    }
    let parsed = match parse_taxonomy_xml(entry.source, limits) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if parsed.target_namespace != entry.namespace_uri {
      return Err(
        InvalidTaxonomy(
          "catalog namespace does not match targetNamespace for '" +
          location +
          "'",
          parsed.offset,
        ),
      )
    }
    schemas.push({ location, schema: parsed, source: entry.source, })
    match limits.check_taxonomy_documents(schemas.length()) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    for imported in parsed.imports {
      let imported_location = match imported.schema_location {
        Some(value) => value
        None =>
          match catalog_location_for_namespace(self, imported.namespace_uri) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
      }
      let imported_entry = match self.entry(imported_location) {
        Some(value) => value
        None =>
          return Err(
            UnresolvedReference(
              "import location '" +
              imported_location +
              "' for namespace '" +
              imported.namespace_uri +
              "'",
            ),
          )
      }
      if imported_entry.namespace_uri != imported.namespace_uri {
        return Err(
          InvalidTaxonomy(
            "import namespace does not match catalog entry '" +
            imported_location +
            "'",
            imported.offset,
          ),
        )
      }
      if !contains_location(queue, imported_location) {
        queue.push(imported_location)
      }
    }
  }
  Ok({ root_location: root, schemas, })
}

///|
fn contains_location_for_resolved(
  schemas : Array[ResolvedTaxonomySchema],
  location : String,
) -> Bool {
  for schema in schemas {
    if schema.location == location {
      return true
    }
  }
  false
}

///|
pub extend TaxonomyCatalogEntry with Eq::{not_equal, equal}

///|
pub extend TaxonomyCatalogEntry with @debug.Debug::{to_repr}

///|
pub extend TaxonomyCatalog with Eq::{not_equal, equal}

///|
pub extend TaxonomyCatalog with @debug.Debug::{to_repr}

///|
pub extend ResolvedTaxonomySchema with Eq::{not_equal, equal}

///|
pub extend ResolvedTaxonomySchema with @debug.Debug::{to_repr}

///|
pub extend ResolvedTaxonomy with Eq::{not_equal, equal}

///|
pub extend ResolvedTaxonomy with @debug.Debug::{to_repr}
