///|
fn schema_source(namespace_uri : String, body : String) -> String {
  "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" targetNamespace=\"" +
  namespace_uri +
  "\">" +
  body +
  "</xs:schema>"
}

///|
fn add_catalog_entry(
  catalog : @xbrlens.TaxonomyCatalog,
  location : String,
  namespace_uri : String,
  body : String,
) -> Unit raise {
  match
    catalog.add(location, namespace_uri, schema_source(namespace_uri, body)) {
    Ok(_) => ()
    Err(err) => fail(err.to_string())
  }
}

///|
fn taxonomy_limits(maximum_documents : Int32) -> @xbrlens.XbrlLimits {
  {
    max_source_bytes: 1_048_576,
    max_xml_depth: 64,
    max_xml_nodes: 50_000,
    max_attributes_per_element: 32,
    max_text_bytes: 524_288,
    max_facts: 20_000,
    max_taxonomy_documents: maximum_documents,
    max_linkbase_arcs: 20_000,
  }
}

///|
test "offline resolver follows schema imports across a cycle" {
  let catalog = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    catalog, "root.xsd", "urn:root", "<xs:import namespace=\"urn:child\" schemaLocation=\"child.xsd\"/><xs:element name=\"Root\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\"/>",
  )
  add_catalog_entry(
    catalog, "child.xsd", "urn:child", "<xs:import namespace=\"urn:root\" schemaLocation=\"root.xsd\"/><xs:element name=\"Child\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\"/>",
  )
  let resolved = match
    catalog.resolve("root.xsd", @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(resolved.root_location, "root.xsd")
  assert_eq(resolved.schemas.length(), 2)
  assert_true(resolved.schema("child.xsd") is Some(_))
  assert_true(resolved.concept("urn:root", "Root") is Some(_))
  assert_true(resolved.concept("urn:child", "Child") is Some(_))
}

///|
test "offline resolver can locate a location-less import by namespace" {
  let catalog = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    catalog, "root.xsd", "urn:root", "<xs:import namespace=\"urn:child\"/><xs:element name=\"Root\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\"/>",
  )
  add_catalog_entry(
    catalog, "child.xsd", "urn:child", "<xs:element name=\"Child\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\"/>",
  )
  let resolved = match
    catalog.resolve("root.xsd", @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(resolved.schemas.length(), 2)
}

///|
test "offline resolver reports missing and ambiguous resources" {
  let missing = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    missing, "root.xsd", "urn:root", "<xs:import namespace=\"urn:child\" schemaLocation=\"child.xsd\"/>",
  )
  assert_true(
    missing.resolve("root.xsd", @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.UnresolvedReference(_)),
  )
  let ambiguous = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    ambiguous, "root.xsd", "urn:root", "<xs:import namespace=\"urn:child\"/>",
  )
  add_catalog_entry(ambiguous, "child-a.xsd", "urn:child", "")
  add_catalog_entry(ambiguous, "child-b.xsd", "urn:child", "")
  assert_true(
    ambiguous.resolve("root.xsd", @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.UnresolvedReference(_)),
  )
}

///|
test "offline resolver verifies declared import namespaces" {
  let catalog = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    catalog, "root.xsd", "urn:root", "<xs:import namespace=\"urn:expected\" schemaLocation=\"child.xsd\"/>",
  )
  add_catalog_entry(catalog, "child.xsd", "urn:actual", "")
  assert_true(
    catalog.resolve("root.xsd", @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidTaxonomy(_, _)),
  )
}

///|
test "offline resolver enforces taxonomy document limits" {
  let catalog = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(
    catalog, "root.xsd", "urn:root", "<xs:import namespace=\"urn:child\" schemaLocation=\"child.xsd\"/>",
  )
  add_catalog_entry(catalog, "child.xsd", "urn:child", "")
  assert_true(
    catalog.resolve("root.xsd", taxonomy_limits(1))
    is Err(@xbrlens.LimitExceeded("taxonomy documents", 1, 2)),
  )
}

///|
test "catalog rejects duplicate locations" {
  let catalog = @xbrlens.TaxonomyCatalog::new()
  add_catalog_entry(catalog, "root.xsd", "urn:root", "")
  assert_true(
    catalog.add("root.xsd", "urn:other", schema_source("urn:other", ""))
    is Err(@xbrlens.InvalidTaxonomy(_, _)),
  )
}
