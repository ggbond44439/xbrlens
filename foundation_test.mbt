///|
fn qname_ok(
  namespace_uri : String,
  local_name : String,
) -> @xbrlens.QName raise {
  match @xbrlens.QName::new(namespace_uri, local_name) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
test "qname expands and compares by expanded name" {
  let name = qname_ok("urn:example", "Revenue")
  assert_eq(name.expanded(), "{urn:example}Revenue")
  assert_true(name.matches("urn:example", "Revenue"))
  assert_false(name.matches("urn:other", "Revenue"))
}

///|
test "qname resolution honours nearest namespace binding" {
  let bindings = [
    @xbrlens.NamespaceBinding::new("", "urn:old"),
    @xbrlens.NamespaceBinding::new("us-gaap", "urn:old-gaap"),
    @xbrlens.NamespaceBinding::new("us-gaap", "urn:new-gaap"),
  ]
  let name = match @xbrlens.resolve_qname("us-gaap:Revenue", bindings, false) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(name.expanded(), "{urn:new-gaap}Revenue")
  let default_name = match @xbrlens.resolve_qname("Revenue", bindings, true) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(default_name.expanded(), "{urn:old}Revenue")
}

///|
test "limits reject invalid and excess values" {
  let zero : @xbrlens.XbrlLimits = {
    max_source_bytes: 0,
    max_xml_depth: 1,
    max_xml_nodes: 1,
    max_attributes_per_element: 1,
    max_text_bytes: 1,
    max_facts: 1,
    max_taxonomy_documents: 1,
    max_linkbase_arcs: 1,
  }
  assert_true(
    @xbrlens.XbrlLimits::validate(zero)
    is Err(@xbrlens.InvalidLimit("max_source_bytes", 0)),
  )
  let limits = @xbrlens.XbrlLimits::strict()
  assert_true(
    limits.check_source(limits.max_source_bytes + 1)
    is Err(@xbrlens.LimitExceeded(_, _, _)),
  )
}
