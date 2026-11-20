///|
fn validation_taxonomy() -> @xbrlens.ResolvedTaxonomy raise {
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
fn validation_linkbase(
  weight_a : String,
  weight_b : String,
) -> @xbrlens.XbrlLinkbase raise {
  let body = "<link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:calc:total\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"Total\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"PartA\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartB\" xlink:label=\"PartB\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartA\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"" +
    weight_a +
    "\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartB\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"" +
    weight_b +
    "\"/></link:calculationLink>"
  let source = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">" +
    body +
    "</link:linkbase>"
  match @xbrlens.parse_linkbase_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
fn validation_instance(
  total : String,
  part_a : String,
  part_b : String,
  child_unit : String,
) -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:calc\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><xbrli:unit id=\"eur\"><xbrli:measure>iso4217:EUR</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">" +
    total +
    "</fin:Total><fin:PartA contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">" +
    part_a +
    "</fin:PartA><fin:PartB contextRef=\"c\" unitRef=\"" +
    child_unit +
    "\" decimals=\"2\">" +
    part_b +
    "</fin:PartB></xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
test "weighted calculation validation reports exact matching facts" {
  let report = match
    @xbrlens.check_calculations(
      validation_linkbase("2", "-0.5"),
      validation_taxonomy(),
      validation_instance("150", "100", "100", "usd"),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(report.checks.length(), 1)
  assert_true(report.is_valid())
  assert_eq(report.checks[0].expected.to_canonical_string(), "150")
  assert_eq(report.checks[0].actual.to_canonical_string(), "150")
  assert_eq(report.checks[0].child_count, 2)
}

///|
test "calculation mismatch exposes expected and actual values" {
  let linkbase = validation_linkbase("1", "1")
  let report = match
    linkbase.check_calculations(
      validation_taxonomy(),
      validation_instance("301", "100", "200", "usd"),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_false(report.is_valid())
  assert_eq(report.mismatches().length(), 1)
  assert_eq(report.checks[0].expected.to_canonical_string(), "300")
  assert_eq(report.checks[0].actual.to_canonical_string(), "301")
}

///|
test "calculation validation rejects inconsistent units and non-decimal facts" {
  let unit_error = match
    @xbrlens.check_calculations(
      validation_linkbase("1", "1"),
      validation_taxonomy(),
      validation_instance("300", "100", "200", "eur"),
    ) {
    Ok(_) => fail("expected unit mismatch")
    Err(err) => err
  }
  assert_true(unit_error is @xbrlens.InvalidFact(_, _))
  let decimal_error = match
    @xbrlens.check_calculations(
      validation_linkbase("1", "1"),
      validation_taxonomy(),
      validation_instance("not-a-number", "100", "200", "usd"),
    ) {
    Ok(_) => fail("expected decimal mismatch")
    Err(err) => err
  }
  assert_true(decimal_error is @xbrlens.InvalidFact(_, _))
}

///|
test "calculation validation skips groups without a matching child fact" {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:calc\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">1</fin:Total></xbrli:xbrl>"
  let instance = match
    @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  let report = match
    @xbrlens.check_calculations(
      validation_linkbase("1", "1"),
      validation_taxonomy(),
      instance,
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(report.checks.length(), 0)
}
