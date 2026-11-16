///|
fn parse_xml_ok(source : StringView) -> @xbrlens.XmlDocument raise {
  match @xbrlens.parse_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(document) => document
    Err(err) => fail(err.to_string())
  }
}

///|
fn parse_xml_err(source : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.parse_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(_) => fail("expected XML parsing to fail")
    Err(err) => err
  }
}

///|
fn xml_limits(
  source_bytes : Int32,
  depth : Int32,
  nodes : Int32,
  attributes : Int32,
  text_bytes : Int32,
) -> @xbrlens.XbrlLimits {
  {
    max_source_bytes: source_bytes,
    max_xml_depth: depth,
    max_xml_nodes: nodes,
    max_attributes_per_element: attributes,
    max_text_bytes: text_bytes,
    max_facts: 10,
    max_taxonomy_documents: 10,
    max_linkbase_arcs: 10,
  }
}

///|
test "XML parser expands element namespaces and leaves unprefixed attributes unqualified" {
  let document = parse_xml_ok(
    "<root xmlns=\"urn:default\" xmlns:x=\"urn:extra\" x:flag=\"yes\" plain=\"1\"><x:child/></root>",
  )
  assert_eq(document.root.name.expanded(), "{urn:default}root")
  assert_eq(document.root.attribute("urn:extra", "flag"), Some("yes"))
  assert_eq(document.root.attribute("", "plain"), Some("1"))
  assert_eq(document.root.children[0].name.expanded(), "{urn:extra}child")
}

///|
test "XML parser applies the nearest default namespace binding" {
  let document = parse_xml_ok(
    "<r xmlns=\"urn:outer\"><a xmlns=\"urn:inner\"><b/></a><c/></r>",
  )
  assert_eq(document.root.name.expanded(), "{urn:outer}r")
  assert_eq(document.root.children[0].name.expanded(), "{urn:inner}a")
  assert_eq(
    document.root.children[0].children[0].name.expanded(),
    "{urn:inner}b",
  )
  assert_eq(document.root.children[1].name.expanded(), "{urn:outer}c")
}

///|
test "XML parser decodes entities and preserves CDATA content" {
  let document = parse_xml_ok(
    "<r value=\"&lt;&amp;&#65;&#x42;\">x&amp;y<![CDATA[<z & raw>]]></r>",
  )
  assert_eq(document.root.attribute("", "value"), Some("<&AB"))
  assert_eq(document.root.text, "x&y<z & raw>")
}

///|
test "XML parser accepts declaration comments processing instructions and empty elements" {
  let document = parse_xml_ok(
    "\u{FEFF}<?xml version=\"1.0\"?><!-- before --><?route keep?><root><?inside ok?><empty/><!-- after --></root><?after done?>",
  )
  assert_eq(document.root.name.local_name, "root")
  assert_eq(document.root.children.length(), 1)
  assert_eq(document.root.children[0].name.local_name, "empty")
  assert_eq(document.root.children[0].text, "")
}

///|
test "XML parser rejects malformed structure" {
  assert_true(parse_xml_err("<a><b></a>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<a/><b/>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<a x=\"1\" x=\"2\"/>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<a x=\"<\"/>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<a>&unknown;</a>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<p:a/>") is @xbrlens.MissingNamespace("p", _))
}

///|
test "XML parser rejects duplicate expanded attributes" {
  let error = parse_xml_err(
    "<r xmlns:a=\"urn:same\" xmlns:b=\"urn:same\" a:x=\"1\" b:x=\"2\"/>",
  )
  assert_true(error is @xbrlens.XmlSyntax(_, _))
}

///|
test "XML parser rejects unsafe declarations and invalid code points" {
  assert_true(
    parse_xml_err(
      "<!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r>&x;</r>",
    )
    is @xbrlens.UnsafeXml(_, _),
  )
  assert_true(parse_xml_err("<r>&#0;</r>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<r>&#xD800;</r>") is @xbrlens.XmlSyntax(_, _))
  assert_true(parse_xml_err("<r>&#x110000;</r>") is @xbrlens.XmlSyntax(_, _))
  assert_true(
    parse_xml_err("<r><?xml version=\"1.0\"?></r>") is @xbrlens.XmlSyntax(_, _),
  )
}

///|
test "XML parser rejects reserved namespace declarations" {
  assert_true(parse_xml_err("<r xmlns:p=\"\"/>") is @xbrlens.XmlSyntax(_, _))
  assert_true(
    parse_xml_err("<r xmlns:xmlns=\"urn:x\"/>") is @xbrlens.XmlSyntax(_, _),
  )
  assert_true(
    parse_xml_err("<r xmlns:xml=\"urn:wrong\"/>") is @xbrlens.XmlSyntax(_, _),
  )
}

///|
test "XML parser enforces depth node attribute and text limits" {
  let depth_source = "<a><b/></a>"
  assert_true(
    @xbrlens.parse_xml(depth_source, xml_limits(100, 1, 10, 10, 10))
    is Err(@xbrlens.LimitExceeded("XML depth", 1, 2)),
  )
  let node_source = "<a><b/></a>"
  assert_true(
    @xbrlens.parse_xml(node_source, xml_limits(100, 10, 1, 10, 10))
    is Err(@xbrlens.LimitExceeded("XML nodes", 1, 2)),
  )
  let attribute_source = "<a x=\"1\" y=\"2\"/>"
  assert_true(
    @xbrlens.parse_xml(attribute_source, xml_limits(100, 10, 10, 1, 10))
    is Err(@xbrlens.LimitExceeded("XML attributes", 1, 2)),
  )
  let text_source = "<a>abc</a>"
  assert_true(
    @xbrlens.parse_xml(text_source, xml_limits(100, 10, 10, 10, 2))
    is Err(@xbrlens.LimitExceeded("text bytes", 2, 3)),
  )
}

///|
test "XML parser counts text across nested elements" {
  let source = "<a>abc<b>def</b></a>"
  assert_true(
    @xbrlens.parse_xml(source, xml_limits(100, 10, 10, 10, 5))
    is Err(@xbrlens.LimitExceeded("text bytes", 5, 6)),
  )
}

///|
test "XML parser rejects source over the configured limit" {
  let source = "<root/>"
  assert_true(
    @xbrlens.parse_xml(source, xml_limits(3, 10, 10, 10, 10))
    is Err(@xbrlens.LimitExceeded("source bytes", 3, _)),
  )
}
