///|
fn precision_instance() -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:calc\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" precision=\"3\">125</fin:Total><fin:PartA contextRef=\"c\" unitRef=\"usd\" precision=\"3\">100</fin:PartA><fin:PartB contextRef=\"c\" unitRef=\"usd\" precision=\"2\">25</fin:PartB></xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
fn rounded_decimal_instance(parent : String) -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:calc\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" decimals=\"-6\">" +
    parent +
    "</fin:Total><fin:PartA contextRef=\"c\" unitRef=\"usd\" decimals=\"-6\">2000000</fin:PartA><fin:PartB contextRef=\"c\" unitRef=\"usd\" decimals=\"-6\">3000000</fin:PartB></xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
fn semantic_instance() -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:calc\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"parent\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:context id=\"children\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd-a\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><xbrli:unit id=\"usd-b\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"parent\" unitRef=\"usd-a\" decimals=\"2\">3</fin:Total><fin:PartA contextRef=\"children\" unitRef=\"usd-b\" decimals=\"2\">1</fin:PartA><fin:PartB contextRef=\"children\" unitRef=\"usd-b\" decimals=\"2\">2</fin:PartB></xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
test "precision metadata creates an overlap-aware calculation decision" {
  let linkbase = validation_linkbase("1", "1")
  let report = match
    linkbase.check_calculations(validation_taxonomy(), precision_instance()) {
    Ok(report) => report
    Err(err) => fail(err.to_string())
  }
  assert_true(report.is_valid())
  assert_true(
    report.checks[0].expected_high.compare(report.checks[0].actual_low) >= 0,
  )
}

///|
test "negative decimals produce an accuracy interval rather than exact equality" {
  let linkbase = validation_linkbase("1", "1")
  let rounded = match
    linkbase.check_calculations(
      validation_taxonomy(),
      rounded_decimal_instance("5400000"),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_true(rounded.is_valid())
  let outside = match
    linkbase.check_calculations(
      validation_taxonomy(),
      rounded_decimal_instance("7000000"),
    ) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_false(outside.is_valid())
}

///|
test "context and unit identities are matched by semantics" {
  let source = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:calc:total\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"Total\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartA\" xlink:label=\"PartA\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#PartB\" xlink:label=\"PartB\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartA\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"PartB\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink></link:linkbase>"
  let linkbase = match
    @xbrlens.parse_linkbase_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  let report = match
    linkbase.check_calculations(validation_taxonomy(), semantic_instance()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_true(report.is_valid())
}
