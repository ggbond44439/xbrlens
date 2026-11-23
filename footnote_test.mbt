///|
test "linkbase parses footnote links and role references" {
  let source = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><link:roleRef roleURI=\"urn:role:note\" xlink:type=\"simple\" xlink:href=\"tax.xsd#role\"/><link:arcroleRef arcroleURI=\"http://www.xbrl.org/2003/arcrole/fact-footnote\" xlink:type=\"simple\" xlink:href=\"tax.xsd#arc\"/><link:footnoteLink xlink:type=\"extended\" xlink:role=\"urn:footnote:link\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#fact\" xlink:label=\"fact\"/><link:footnote xlink:type=\"resource\" xlink:label=\"note\" xlink:role=\"urn:role:note\" xml:lang=\"en\">See note 1</link:footnote><link:footnoteArc xlink:type=\"arc\" xlink:from=\"fact\" xlink:to=\"note\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/fact-footnote\"/></link:footnoteLink></link:linkbase>"
  let linkbase = match @xbrlens.parse_linkbase_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(linkbase.role_refs.length(), 1)
  assert_eq(linkbase.arcrole_refs.length(), 1)
  assert_eq(linkbase.footnote_links.length(), 1)
  assert_eq(linkbase.footnote_links[0].footnotes[0].text, "See note 1")
  assert_eq(linkbase.footnote_links[0].footnotes[0].language, Some("en"))
}

///|
test "linkbase rejects invalid footnote endpoints and arcroles" {
  let invalid = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><link:footnoteLink xlink:type=\"extended\" xlink:role=\"urn:link\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#fact\" xlink:label=\"fact\"/><link:footnote xlink:type=\"resource\" xlink:label=\"note\" xlink:role=\"urn:role\">Note</link:footnote><link:footnoteArc xlink:type=\"arc\" xlink:from=\"fact\" xlink:to=\"missing\" xlink:arcrole=\"http://www.xbrl.org/2003/arcrole/fact-footnote\"/></link:footnoteLink></link:linkbase>"
  assert_true(
    @xbrlens.parse_linkbase_xml(invalid, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidLinkbase(_, _)),
  )
  let wrong = "<link:linkbase xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><link:footnoteLink xlink:type=\"extended\" xlink:role=\"urn:link\"><link:loc xlink:type=\"locator\" xlink:href=\"tax.xsd#fact\" xlink:label=\"fact\"/><link:footnote xlink:type=\"resource\" xlink:label=\"note\" xlink:role=\"urn:role\">Note</link:footnote><link:footnoteArc xlink:type=\"arc\" xlink:from=\"fact\" xlink:to=\"note\" xlink:arcrole=\"urn:wrong\"/></link:footnoteLink></link:linkbase>"
  assert_true(
    @xbrlens.parse_linkbase_xml(wrong, @xbrlens.XbrlLimits::strict())
    is Err(@xbrlens.InvalidLinkbase(_, _)),
  )
}