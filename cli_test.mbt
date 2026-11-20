///|
fn cli_instance(value : String) -> String {
  "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:cli\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">" +
  value +
  "</fin:Total></xbrli:xbrl>"
}

///|
fn cli_calc_instance(total : String, part : String) -> String {
  "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:cli\" xmlns:iso4217=\"http://www.xbrl.org/2003/iso4217\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><xbrli:unit id=\"usd\"><xbrli:measure>iso4217:USD</xbrli:measure></xbrli:unit><fin:Total contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">" +
  total +
  "</fin:Total><fin:Part contextRef=\"c\" unitRef=\"usd\" decimals=\"2\">" +
  part +
  "</fin:Part></xbrli:xbrl>"
}

///|
fn cli_taxonomy() -> String {
  "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" targetNamespace=\"urn:cli\"><xs:element name=\"Total\" id=\"Total\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\"/><xs:element name=\"Part\" id=\"Part\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\"/></xs:schema>"
}

///|
fn cli_linkbase() -> String {
  "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><link:calculationLink xlink:type=\"extended\" xlink:role=\"urn:cli:calc\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Total\" xlink:label=\"Total\"/><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#Part\" xlink:label=\"Part\"/><link:calculationArc xlink:type=\"arc\" xlink:from=\"Total\" xlink:to=\"Part\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/summation-item\" weight=\"1\"/></link:calculationLink></link:linkbase>"
}

///|
test "CLI parses global options and command names" {
  let invocation = match
    @xbrlens.parse_invocation(["--json", "inspect", "<r/>"]) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(invocation.command, @xbrlens.Inspect)
  assert_eq(invocation.json, true)
  assert_eq(invocation.args.length(), 1)
  assert_eq(@xbrlens.run([]).exit_code, 0)
  assert_true(@xbrlens.run(["version"]).stdout.has_prefix("xbrlens "))
}

///|
test "CLI inspect and facts commands use the instance model" {
  let instance = cli_instance("10")
  let inspect = @xbrlens.run(["--json", "inspect", instance])
  assert_eq(inspect.exit_code, 0)
  assert_true(inspect.stdout.contains("\"facts\":1"))
  let facts = @xbrlens.run(["facts", instance])
  assert_eq(facts.exit_code, 0)
  assert_true(facts.stdout.has_prefix("["))
  let csv = @xbrlens.run(["facts", "--csv", instance])
  assert_true(csv.stdout.has_prefix("fact_id,concept,namespace"))
}

///|
test "CLI validate reports integrity and uses exit status for errors" {
  let valid = @xbrlens.run(["validate", cli_instance("10")])
  assert_eq(valid.exit_code, 0)
  assert_true(valid.stdout.contains("errors: 0"))
  let duplicate = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:cli\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><fin:Total contextRef=\"c\">1</fin:Total><fin:Total contextRef=\"c\">2</fin:Total></xbrli:xbrl>"
  let invalid = @xbrlens.run(["validate", duplicate])
  assert_eq(invalid.exit_code, 1)
  assert_true(invalid.stderr.contains("conflicting-duplicate"))
}

///|
test "CLI calc parses taxonomy and linkbase inputs" {
  let result = @xbrlens.run([
    "calc",
    cli_calc_instance("10", "10"),
    cli_taxonomy(),
    cli_linkbase(),
  ])
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.contains("ok:"))
  let mismatch_instance = cli_calc_instance("11", "10")
  let mismatch = @xbrlens.run([
    "calc",
    mismatch_instance,
    cli_taxonomy(),
    cli_linkbase(),
  ])
  assert_eq(mismatch.exit_code, 1)
  assert_true(mismatch.stderr.contains("mismatch:"))
}

///|
test "CLI diff reports fact changes and handles bad invocations" {
  let diff = @xbrlens.run(["diff", cli_instance("10"), cli_instance("11")])
  assert_eq(diff.exit_code, 0)
  assert_true(diff.stdout.contains("changed: 2"))
  assert_eq(@xbrlens.run(["missing"]).exit_code, 2)
  assert_eq(@xbrlens.run(["inspect"]).exit_code, 2)
  assert_eq(@xbrlens.run(["facts", "--unknown", "x"]).exit_code, 2)
}
