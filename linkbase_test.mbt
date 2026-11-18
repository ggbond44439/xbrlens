///|
fn linkbase_wrap(body : String) -> String {
  "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:label=\"http://www.xbrl.org/2003/role\">" +
  body +
  "</link:linkbase>"
}

///|
fn linkbase_ok(source : StringView) -> @xbrlens.XbrlLinkbase raise {
  match @xbrlens.parse_linkbase_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
fn linkbase_err(source : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.parse_linkbase_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(_) => fail("expected linkbase parsing to fail")
    Err(err) => err
  }
}

///|
fn linkbase_taxonomy() -> @xbrlens.ResolvedTaxonomy raise {
  let source = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" targetNamespace=\"urn:fin\"><xs:element name=\"Assets\" id=\"Assets\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/><xs:element name=\"CurrentAssets\" id=\"CurrentAssets\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/><xs:element name=\"Cash\" id=\"Cash\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/></xs:schema>"
  let schema = match
    @xbrlens.parse_taxonomy_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  {
    root_location: "tax.xsd",
    schemas: [{ location: "tax.xsd", schema, source, }],
  }
}

///|
fn linkbase_limits(max_arcs : Int32) -> @xbrlens.XbrlLimits {
  {
    max_source_bytes: 1_048_576,
    max_xml_depth: 64,
    max_xml_nodes: 50_000,
    max_attributes_per_element: 32,
    max_text_bytes: 524_288,
    max_facts: 20_000,
    max_taxonomy_documents: 128,
    max_linkbase_arcs: max_arcs,
  }
}

///|
test "linkbase parses labels presentation links and arc metadata" {
  let body = "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:link:labels\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:label xlink:type=\"resource\" xlink:label=\"AssetsLabel\" xlink:role=\"http://www.xbrl.org/2003/role/label\" xml:lang=\"en\">Total assets</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"AssetsLoc\" xlink:to=\"AssetsLabel\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\" order=\"1\" priority=\"2\"/></link:labelLink><link:presentationLink xlink:type=\"extended\" xlink:role=\"urn:link:balance-sheet\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#CurrentAssets\" xlink:label=\"CurrentAssetsLoc\"/><link:presentationArc xlink:type=\"arc\" xlink:from=\"AssetsLoc\" xlink:to=\"CurrentAssetsLoc\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/parent-child\" order=\"2.5\" priority=\"3\" preferredLabel=\"label:label\"/></link:presentationLink>"
  let linkbase = linkbase_ok(linkbase_wrap(body))
  assert_eq(linkbase.label_links.length(), 1)
  assert_eq(linkbase.presentation_links.length(), 1)
  assert_eq(linkbase.label_links[0].locators.length(), 1)
  assert_eq(linkbase.label_links[0].labels[0].language, Some("en"))
  assert_eq(linkbase.label_links[0].labels[0].text, "Total assets")
  assert_eq(linkbase.label_links[0].arcs[0].priority, 2)
  assert_eq(linkbase.label_links[0].arcs[0].arc_use, @xbrlens.Unspecified)
  assert_eq(
    linkbase.presentation_links[0].arcs[0].order.unwrap().to_canonical_string(),
    "2.5",
  )
}

///|
test "linkbase resolves concept labels and presentation relations against taxonomy ids" {
  let body = "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:link:labels\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:label xlink:type=\"resource\" xlink:label=\"AssetsLabel\" xlink:role=\"http://www.xbrl.org/2003/role/label\" xml:lang=\"en\">Total assets</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"AssetsLoc\" xlink:to=\"AssetsLabel\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/></link:labelLink><link:presentationLink xlink:type=\"extended\" xlink:role=\"urn:link:balance-sheet\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#CurrentAssets\" xlink:label=\"CurrentAssetsLoc\"/><link:presentationArc xlink:type=\"arc\" xlink:from=\"AssetsLoc\" xlink:to=\"CurrentAssetsLoc\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/parent-child\" order=\"2.5\" priority=\"3\" preferredLabel=\"label:label\"/></link:presentationLink>"
  let linkbase = linkbase_ok(linkbase_wrap(body))
  let taxonomy = linkbase_taxonomy()
  let labels = match linkbase.labels(taxonomy) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(labels.length(), 1)
  assert_eq(labels[0].concept.expanded(), "{urn:fin}Assets")
  assert_eq(labels[0].label_role_uri, "http://www.xbrl.org/2003/role/label")
  assert_eq(labels[0].text, "Total assets")
  assert_eq(labels[0].priority, 0)
  let relations = match linkbase.presentation_relations(taxonomy) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(relations.length(), 1)
  assert_eq(relations[0].parent.expanded(), "{urn:fin}Assets")
  assert_eq(relations[0].child.expanded(), "{urn:fin}CurrentAssets")
  assert_eq(relations[0].order.unwrap().to_canonical_string(), "2.5")
  assert_eq(relations[0].priority, 3)
  assert_eq(
    relations[0].preferred_label.unwrap().expanded(),
    "{http://www.xbrl.org/2003/role}label",
  )
}

///|
test "linkbase excludes prohibited arcs from resolved networks" {
  let body = "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:link:labels\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:label xlink:type=\"resource\" xlink:label=\"AllowedLabel\" xlink:role=\"http://www.xbrl.org/2003/role/label\">Allowed</link:label><link:label xlink:type=\"resource\" xlink:label=\"BlockedLabel\" xlink:role=\"http://www.xbrl.org/2003/role/terseLabel\">Blocked</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"AssetsLoc\" xlink:to=\"AllowedLabel\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/><link:labelArc xlink:type=\"arc\" xlink:use=\"prohibited\" xlink:from=\"AssetsLoc\" xlink:to=\"BlockedLabel\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/></link:labelLink><link:presentationLink xlink:type=\"extended\" xlink:role=\"urn:link:balance-sheet\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"AssetsLoc\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#CurrentAssets\" xlink:label=\"CurrentAssetsLoc\"/><link:presentationArc xlink:type=\"arc\" xlink:use=\"prohibited\" xlink:from=\"AssetsLoc\" xlink:to=\"CurrentAssetsLoc\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/parent-child\"/></link:presentationLink>"
  let linkbase = linkbase_ok(linkbase_wrap(body))
  let taxonomy = linkbase_taxonomy()
  let labels = match linkbase.labels(taxonomy) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(labels.length(), 1)
  assert_eq(labels[0].text, "Allowed")
  let relations = match linkbase.presentation_relations(taxonomy) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(relations.length(), 0)
}

///|
test "linkbase rejects malformed roots roles arcroles and endpoints" {
  assert_true(linkbase_err("<linkbase/>") is @xbrlens.InvalidLinkbase(_, _))
  let missing_role = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\"><link:labelLink xlink:type=\"extended\"/></link:linkbase>"
  assert_true(
    linkbase_err(missing_role) is @xbrlens.MissingNamespace("xlink", _),
  )
  let wrong_arcrole = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"a\"/><link:label xlink:type=\"resource\" xlink:label=\"l\" xlink:role=\"urn:role\">A</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"l\" xlink:arcrole=\"urn:wrong\"/></link:labelLink>",
  )
  assert_true(linkbase_err(wrong_arcrole) is @xbrlens.InvalidLinkbase(_, _))
  let missing_endpoint = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"a\"/><link:label xlink:type=\"resource\" xlink:label=\"l\" xlink:role=\"urn:role\">A</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"missing\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/></link:labelLink>",
  )
  assert_true(linkbase_err(missing_endpoint) is @xbrlens.InvalidLinkbase(_, _))
}

///|
test "linkbase rejects duplicate labels and invalid ordering metadata" {
  let duplicate_locator = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Cash\" xlink:label=\"a\"/></link:labelLink>",
  )
  assert_true(linkbase_err(duplicate_locator) is @xbrlens.InvalidLinkbase(_, _))
  let duplicate_label = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:label xlink:type=\"resource\" xlink:label=\"l\" xlink:role=\"urn:r1\">A</link:label><link:label xlink:type=\"resource\" xlink:label=\"l\" xlink:role=\"urn:r2\">B</link:label></link:labelLink>",
  )
  assert_true(linkbase_err(duplicate_label) is @xbrlens.InvalidLinkbase(_, _))
  let bad_order = linkbase_wrap(
    "<link:presentationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Cash\" xlink:label=\"b\"/><link:presentationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"b\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/parent-child\" order=\"nope\"/></link:presentationLink>",
  )
  assert_true(linkbase_err(bad_order) is @xbrlens.InvalidDecimal(_, _))
}

///|
test "linkbase reports unresolved concept ids and enforces arc limits" {
  let source = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Missing\" xlink:label=\"a\"/><link:label xlink:type=\"resource\" xlink:label=\"l\" xlink:role=\"urn:role\">A</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"l\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/></link:labelLink>",
  )
  let linkbase = linkbase_ok(source)
  assert_true(
    linkbase.labels(linkbase_taxonomy()) is Err(@xbrlens.UnresolvedReference(_)),
  )
  let over_limit = linkbase_wrap(
    "<link:labelLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Assets\" xlink:label=\"a\"/><link:label xlink:type=\"resource\" xlink:label=\"l1\" xlink:role=\"urn:r1\">A</link:label><link:label xlink:type=\"resource\" xlink:label=\"l2\" xlink:role=\"urn:r2\">B</link:label><link:labelArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"l1\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/><link:labelArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"l2\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/concept-label\"/></link:labelLink>",
  )
  assert_true(
    @xbrlens.parse_linkbase_xml(over_limit, linkbase_limits(1))
    is Err(@xbrlens.LimitExceeded("linkbase arcs", 1, 2)),
  )
}
