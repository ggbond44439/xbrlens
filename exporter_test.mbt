///|
fn export_instance() -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:xbrldi=\"http://xbrl.org/2006/xbrldi\" xmlns:fin=\"urn:export\" xmlns:gaap=\"urn:gaap\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:cik\">0000000001</xbrli:identifier><xbrli:segment><xbrldi:explicitMember dimension=\"gaap:SegmentAxis\">gaap:RetailMember</xbrldi:explicitMember></xbrli:segment></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Amount contextRef=\"c\" unitRef=\"usd\" decimals=\"2\" id=\"amount\">100.50</fin:Amount><fin:Label contextRef=\"c\" id=\"label\">A,B &quot;Q&quot;</fin:Label></xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
test "fact exporter builds normalized rows with context units and dimensions" {
  let rows = match @xbrlens.export_rows(export_instance()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].concept, "{urn:export}Amount")
  assert_eq(rows[0].unit_ref, Some("usd"))
  assert_eq(rows[0].canonical_value, Some("100.5"))
  assert_eq(rows[0].period_type, "instant")
  assert_eq(
    rows[0].dimensions_json,
    "[{\"dimension\":\"{urn:gaap}SegmentAxis\",\"kind\":\"explicit\",\"member\":\"{urn:gaap}RetailMember\"}]",
  )
}

///|
test "fact exporter serializes JSON with stable fields and escaped text" {
  let json = match @xbrlens.export_json(export_instance()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_true(json.has_prefix("["))
  assert_true(json.contains("\"canonicalValue\":\"100.5\""))
  assert_true(
    json.contains("\"dimensions\":[{\"dimension\":\"{urn:gaap}SegmentAxis\""),
  )
  assert_true(json.contains("\"value\":\"A,B \\\"Q\\\"\""))
}

///|
test "fact exporter serializes CSV headers and RFC4180 quoting" {
  let csv = match @xbrlens.export_csv(export_instance()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_true(csv.has_prefix("fact_id,concept,namespace,local_name"))
  assert_true(csv.contains("\"A,B \"\"Q\"\"\""))
  assert_true(csv.contains("100.5"))
  assert_true(csv.contains("{urn:gaap}SegmentAxis"))
}
