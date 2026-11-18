///|
fn security_limits(
  source : Int32,
  depth : Int32,
  nodes : Int32,
  attrs : Int32,
  text : Int32,
) -> @xbrlens.XbrlLimits {
  {
    max_source_bytes: source,
    max_xml_depth: depth,
    max_xml_nodes: nodes,
    max_attributes_per_element: attrs,
    max_text_bytes: text,
    max_facts: 10,
    max_taxonomy_documents: 10,
    max_linkbase_arcs: 10,
  }
}

///|
test "security parser rejects control characters and CDATA injection" {
  let control_source = "<r>" + (1).unsafe_to_char().to_string() + "</r>"
  assert_true(
    @xbrlens.parse_xml(control_source, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.XmlSyntax(_, _)),
  )
  let cdata_source = "<r><![CDATA[" +
    (2).unsafe_to_char().to_string() +
    "]]></r>"
  assert_true(
    @xbrlens.parse_xml(cdata_source, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.XmlSyntax(_, _)),
  )
  assert_true(
    @xbrlens.parse_xml("<r>]]></r>", @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.XmlSyntax(_, _)),
  )
}

///|
test "security parser rejects DTD entity expansion payloads" {
  assert_true(
    @xbrlens.parse_xml(
      "<!DOCTYPE r [<!ENTITY a 'x'><!ENTITY b '&a;&a;&a;'>]><r>&b;</r>",
      @xbrlens.XbrlLimits::strict(),
    )
    is Err(@xbrlens.UnsafeXml(_, _)),
  )
}

///|
test "security parser enforces depth node attribute and text limits" {
  let depth = StringBuilder()
  let mut index = 0
  while index < 70 {
    depth.write_string("<a>")
    index += 1
  }
  index = 0
  while index < 70 {
    depth.write_string("</a>")
    index += 1
  }
  assert_true(
    @xbrlens.parse_xml(depth.to_string(), @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.LimitExceeded("XML depth", _, _)),
  )
  assert_true(
    @xbrlens.parse_xml("<a><b/></a>", security_limits(100, 10, 1, 10, 10))
    is Err(@xbrlens.LimitExceeded("XML nodes", 1, 2)),
  )
  let attributes = StringBuilder()
  attributes.write_string("<a")
  index = 0
  while index < 40 {
    attributes.write_string(" a" + index.to_string() + "=\"x\"")
    index += 1
  }
  attributes.write_string("/>")
  assert_true(
    @xbrlens.parse_xml(attributes.to_string(), @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.LimitExceeded("XML attributes", _, _)),
  )
  assert_true(
    @xbrlens.parse_xml("<a>12345</a>", security_limits(100, 10, 10, 10, 4))
    is Err(@xbrlens.LimitExceeded("text bytes", 4, 5)),
  )
}

///|
test "security audit summarizes a bounded instance" {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:fin=\"urn:audit\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><fin:Value contextRef=\"c\">1</fin:Value></xbrli:xbrl>"
  let audit = match
    @xbrlens.audit_instance_source(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(audit.contexts, 1)
  assert_eq(audit.facts, 1)
  assert_eq(audit.units, 0)
  assert_true(audit.xml_nodes >= 7)
  assert_eq(audit.source_bytes, source.length())
}
