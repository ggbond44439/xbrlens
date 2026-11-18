///|
fn calculation_wrap(body : String) -> String {
  "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">" +
  body +
  "</link:linkbase>"
}

///|
fn calculation_taxonomy() -> @xbrlens.ResolvedTaxonomy raise {
  let source = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" targetNamespace=\"urn:calc\"><xs:element name=\"Total\" id=\"Total\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/><xs:element name=\"PartA\" id=\"PartA\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/><xs:element name=\"PartB\" id=\"PartB\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\"/></xs:schema>"
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
fn calculation_limits(max_arcs : Int32) -> @xbrlens.XbrlLimits {
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
test "calculation linkbase parses weighted arcs and groups relations" {
  let body = "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:calc:total\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"Total\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"PartA\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartB\" xlink:label=\"PartB\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartA\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\" order=\"1\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartB\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"-1.5\" order=\"2\"/><link:calculationArc xlink:type=\"arc\" xlink:use=\"prohibited\" xlink:from=\"Total\" xlink:to=\"PartA\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink>"
  let linkbase = match
    @xbrlens.parse_linkbase_xml(
      calculation_wrap(body),
      @xbrlens.XbrlLimits::strict(),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(linkbase.calculation_links.length(), 1)
  assert_eq(linkbase.calculation_links[0].arcs.length(), 3)
  let relations = match linkbase.calculation_relations(calculation_taxonomy()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(relations.length(), 2)
  assert_eq(relations[0].parent.expanded(), "{urn:calc}Total")
  assert_eq(relations[0].child.expanded(), "{urn:calc}PartA")
  assert_eq(relations[0].weight.to_canonical_string(), "1")
  assert_eq(relations[1].weight.to_canonical_string(), "-1.5")
  let groups = match linkbase.calculation_groups(calculation_taxonomy()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].relations.length(), 2)
}

///|
test "calculation linkbase rejects invalid arc metadata" {
  let missing_weight = calculation_wrap(
    "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"b\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"b\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\"/></link:calculationLink>",
  )
  assert_true(
    @xbrlens.parse_linkbase_xml(missing_weight, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidLinkbase(_, _)),
  )
  let wrong_role = calculation_wrap(
    "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"b\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"b\" xlink:arcrole=\"urn:wrong\" weight=\"1\"/></link:calculationLink>",
  )
  assert_true(
    @xbrlens.parse_linkbase_xml(wrong_role, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidLinkbase(_, _)),
  )
  let missing_endpoint = calculation_wrap(
    "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"a\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"missing\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink>",
  )
  assert_true(
    @xbrlens.parse_linkbase_xml(missing_endpoint, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidLinkbase(_, _)),
  )
}

///|
test "calculation linkbase reports unresolved concepts and enforces arc limits" {
  let body = "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Missing\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"b\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"b\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink>"
  let linkbase = match
    @xbrlens.parse_linkbase_xml(
      calculation_wrap(body),
      @xbrlens.XbrlLimits::strict(),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_true(
    linkbase.calculation_relations(calculation_taxonomy())
    is Err(@xbrlens.UnresolvedReference(_)),
  )
  let over_limit = calculation_wrap(
    "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:r\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"a\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"b\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartB\" xlink:label=\"c\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"b\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"a\" xlink:to=\"c\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink>",
  )
  assert_true(
    @xbrlens.parse_linkbase_xml(over_limit, calculation_limits(1))
    is Err(@xbrlens.LimitExceeded("linkbase arcs", 1, 2)),
  )
}
