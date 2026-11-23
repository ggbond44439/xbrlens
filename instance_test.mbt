///|
fn instance_ok(source : StringView) -> @xbrlens.XbrlInstance raise {
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(instance) => instance
    Err(err) => fail(err.to_string())
  }
}

///|
fn instance_err(source : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(_) => fail("expected instance parsing to fail")
    Err(err) => err
  }
}

///|
test "XBRL instance parses schema references contexts units and facts" {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\" xmlns:us-gaap=\"http://fasb.org/us-gaap/2024\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><link:schemaRef xlink:type=\"simple\" xlink:href=\"sample.xsd\"/><xbrli:context id=\"c1\"><xbrli:entity><xbrli:identifier scheme=\"http://www.sec.gov/CIK\">0000000001</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:context id=\"c2\"><xbrli:entity><xbrli:identifier scheme=\"http://www.sec.gov/CIK\">0000000001</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:startDate>2024-01-01</xbrli:startDate><xbrli:endDate>2024-12-31</xbrli:endDate></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><xbrli:unit id=\"perShare\"><xbrli:divide><xbrli:unitNumerator><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unitNumerator><xbrli:unitDenominator><xbrli:measure>xbrli:shares</xbrli:measure></xbrli:unitDenominator></xbrli:divide></xbrli:unit><us-gaap:Assets contextRef=\"c1\" unitRef=\"usd\" decimals=\"-6\" id=\"f1\">123000000</us-gaap:Assets><us-gaap:EarningsPerShare contextRef=\"c2\" unitRef=\"perShare\" decimals=\"2\" xml:lang=\"en\">1.25</us-gaap:EarningsPerShare><us-gaap:Label contextRef=\"c1\" xsi:nil=\"true\"/></xbrli:xbrl>"
  let instance = instance_ok(source)
  assert_eq(instance.schema_refs.length(), 1)
  assert_eq(instance.schema_refs[0], "sample.xsd")
  assert_eq(instance.contexts.length(), 2)
  assert_eq(instance.units.length(), 2)
  assert_eq(instance.facts.length(), 3)
  assert_eq(instance.contexts[0].period, @xbrlens.Instant("2024-12-31"))
  assert_eq(
    instance.contexts[1].period,
    @xbrlens.Duration("2024-01-01", "2024-12-31"),
  )
  assert_eq(
    instance.facts[0].concept.expanded(),
    "{http://fasb.org/us-gaap/2024}Assets",
  )
  assert_eq(instance.facts[0].unit_ref, Some("usd"))
  assert_eq(instance.facts[0].decimals, Some("-6"))
  assert_eq(instance.facts[1].language, Some("en"))
  assert_true(instance.facts[2].nil)
  let matches = instance.facts_for_context("c1")
  assert_eq(matches.length(), 2)
}

///|
test "XBRL instance resolves divided units and direct lookup helpers" {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"ratio\"><xbrli:divide><xbrli:unitNumerator><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unitNumerator><xbrli:unitDenominator><xbrli:measure>xbrli:shares</xbrli:measure></xbrli:unitDenominator></xbrli:divide></xbrli:unit></xbrli:xbrl>"
  let instance = instance_ok(source)
  assert_true(instance.context("c") is Some(_))
  let unit = match instance.unit("ratio") {
    Some(value) => value
    None => fail("unit lookup failed")
  }
  match unit.unit {
    @xbrlens.Divide(numerator, denominator) => {
      assert_eq(
        numerator[0].expanded(),
        "{http://www.xbrl.org/2003/iso4217}USD",
      )
      assert_eq(
        denominator[0].expanded(),
        "{http://www.xbrl.org/2003/instance}shares",
      )
    }
    _ => fail("expected divided unit")
  }
}

///|
test "XBRL instance rejects duplicate context unit and fact identifiers" {
  let duplicate_context = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context></xbrli:xbrl>"
  assert_true(instance_err(duplicate_context) is @xbrlens.InvalidContext(_, _))
  let duplicate_fact = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:x=\"urn:x\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context><x:Amount contextRef=\"c\" id=\"f\">1</x:Amount><x:Other contextRef=\"c\" id=\"f\">2</x:Other></xbrli:xbrl>"
  assert_true(instance_err(duplicate_fact) is @xbrlens.DuplicateFact("f", _))
}

///|
test "XBRL instance rejects invalid periods and missing required structure" {
  let invalid_date = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-02-30</xbrli:instant></xbrli:period></xbrli:context></xbrli:xbrl>"
  assert_true(instance_err(invalid_date) is @xbrlens.InvalidContext(_, _))
  let reversed = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:startDate>2024-12-31</xbrli:startDate><xbrli:endDate>2024-01-01</xbrli:endDate></xbrli:period></xbrli:context></xbrli:xbrl>"
  assert_true(instance_err(reversed) is @xbrlens.InvalidContext(_, _))
  let missing_identifier = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\"><xbrli:context id=\"c\"><xbrli:entity/><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context></xbrli:xbrl>"
  assert_true(instance_err(missing_identifier) is @xbrlens.InvalidContext(_, _))
}

///|
test "XBRL instance rejects unresolved references and parses tuple facts" {
  let unresolved_context = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:x=\"urn:x\"><x:Amount contextRef=\"missing\">1</x:Amount></xbrli:xbrl>"
  assert_true(
    instance_err(unresolved_context) is @xbrlens.UnresolvedReference(_),
  )
  let unresolved_unit = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:x=\"urn:x\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context><x:Amount contextRef=\"c\" unitRef=\"missing\">1</x:Amount></xbrli:xbrl>"
  assert_true(instance_err(unresolved_unit) is @xbrlens.UnresolvedReference(_))
  let tuple = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:x=\"urn:x\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context><x:Tuple id=\"t\"><x:Child contextRef=\"c\">1</x:Child><x:Nested id=\"n\"><x:Child contextRef=\"c\">2</x:Child></x:Nested></x:Tuple></xbrli:xbrl>"
  let parsed = instance_ok(tuple)
  assert_eq(parsed.facts.length(), 0)
  assert_eq(parsed.tuples.length(), 1)
  assert_eq(parsed.tuples[0].id, Some("t"))
  assert_eq(parsed.tuples[0].facts.length(), 1)
  assert_eq(parsed.tuples[0].tuples.length(), 1)
  assert_eq(parsed.tuples[0].tuples[0].facts[0].value, "2")
}

///|
test "XBRL instance rejects invalid nil values and non-empty nil facts" {
  let prefix = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:x=\"urn:x\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-01-01</xbrli:instant></xbrli:period></xbrli:context>"
  assert_true(
    instance_err(
      prefix + "<x:A contextRef=\"c\" xsi:nil=\"maybe\"/></xbrli:xbrl>",
    )
    is @xbrlens.InvalidFact(_, _),
  )
  assert_true(
    instance_err(
      prefix +
      "<x:A contextRef=\"c\" xsi:nil=\"true\">not empty</x:A></xbrli:xbrl>",
    )
    is @xbrlens.InvalidFact(_, _),
  )
}
