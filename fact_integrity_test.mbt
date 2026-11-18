///|
fn integrity_instance(facts : String) -> @xbrlens.XbrlInstance raise {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:integrity\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><xbrli:unit id=\"eur\"><xbrli:measure>iso4217:EUR</xbrli:measure></xbrli:unit>" +
    facts +
    "</xbrli:xbrl>"
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
test "fact integrity classifies equivalent duplicate numeric facts" {
  let report = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" decimals=\"2\" id=\"f1\">1.0</fin:A><fin:A contextRef=\"c\" unitRef=\"usd\" decimals=\"2\" id=\"f2\">1.00</fin:A>",
  ).fact_integrity()
  assert_eq(report.error_count(), 0)
  assert_eq(report.warning_count(), 1)
  assert_eq(report.diagnostics[0].kind, @xbrlens.ExactDuplicate)
  assert_eq(report.diagnostics[0].fact_ids, ["f1", "f2"])
}

///|
test "fact integrity reports conflicting and nil duplicate facts" {
  let conflicting = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" id=\"f1\">100</fin:A><fin:A contextRef=\"c\" unitRef=\"usd\" id=\"f2\">101</fin:A>",
  ).fact_integrity()
  assert_true(conflicting.has_errors())
  assert_eq(conflicting.error_count(), 1)
  assert_eq(conflicting.diagnostics[0].kind, @xbrlens.ConflictingDuplicate)
  let nil_conflict = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" id=\"f1\">100</fin:A><fin:A contextRef=\"c\" unitRef=\"usd\" id=\"f2\" xsi:nil=\"true\"/>",
  ).fact_integrity()
  assert_true(nil_conflict.has_errors())
  assert_eq(nil_conflict.diagnostics[0].kind, @xbrlens.NilConflict)
}

///|
test "fact integrity warns when the same concept uses multiple units" {
  let report = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" id=\"f1\">100</fin:A><fin:A contextRef=\"c\" unitRef=\"eur\" id=\"f2\">90</fin:A>",
  ).fact_integrity()
  assert_eq(report.error_count(), 0)
  assert_eq(report.warning_count(), 1)
  assert_eq(report.diagnostics[0].kind, @xbrlens.MultipleUnits)
}

///|
test "fact integrity validates decimals and precision metadata" {
  let both = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" decimals=\"2\" precision=\"4\">100</fin:A>",
  ).fact_integrity()
  assert_true(both.has_errors())
  assert_eq(both.diagnostics[0].kind, @xbrlens.DecimalsPrecisionConflict)
  let invalid = integrity_instance(
    "<fin:A contextRef=\"c\" unitRef=\"usd\" decimals=\"many\">100</fin:A><fin:B contextRef=\"c\" unitRef=\"usd\" precision=\"0\">1</fin:B>",
  ).fact_integrity()
  assert_eq(invalid.error_count(), 2)
  assert_eq(invalid.diagnostics[0].kind, @xbrlens.InvalidDecimals)
  assert_eq(invalid.diagnostics[1].kind, @xbrlens.InvalidPrecision)
}
