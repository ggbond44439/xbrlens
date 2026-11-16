///|
fn taxonomy_ok(source : StringView) -> @xbrlens.XbrlSchema raise {
  match @xbrlens.parse_taxonomy_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(schema) => schema
    Err(err) => fail(err.to_string())
  }
}

///|
fn taxonomy_err(source : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.parse_taxonomy_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(_) => fail("expected taxonomy parsing to fail")
    Err(err) => err
  }
}

///|
test "taxonomy parser extracts imports concepts and role types" {
  let source = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:link=\"http://www.xbrl.org/2003/linkbase\" xmlns:us-gaap=\"http://fasb.org/us-gaap/2024\" targetNamespace=\"http://fasb.org/us-gaap/2024\"><xs:import namespace=\"http://www.xbrl.org/2003/instance\" schemaLocation=\"xbrl-instance-2003-12-31.xsd\"/><link:roleType roleURI=\"http://example.com/role/Statements\" id=\"Statements\"><link:definition>Statement roles</link:definition><link:usedOn>link:presentationLink</link:usedOn><link:usedOn>link:calculationLink</link:usedOn></link:roleType><xs:element name=\"Assets\" id=\"us-gaap_Assets\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"instant\" balance=\"debit\" nillable=\"true\"/><xs:element name=\"Revenue\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"duration\" balance=\"credit\" abstract=\"true\"/><xs:element name=\"DisclosureTuple\" type=\"xbrli:tupleType\" substitutionGroup=\"xbrli:tuple\"/><xs:element name=\"roleType\" type=\"link:roleTypeType\"/></xs:schema>"
  let schema = taxonomy_ok(source)
  assert_eq(schema.target_namespace, "http://fasb.org/us-gaap/2024")
  assert_eq(schema.imports.length(), 1)
  assert_eq(
    schema.imports[0].schema_location,
    Some("xbrl-instance-2003-12-31.xsd"),
  )
  assert_eq(schema.concepts.length(), 3)
  let assets = match schema.concept("http://fasb.org/us-gaap/2024", "Assets") {
    Some(value) => value
    None => fail("missing Assets concept")
  }
  assert_eq(assets.kind, @xbrlens.Item)
  assert_eq(assets.period_type, @xbrlens.Instant)
  assert_eq(assets.balance, @xbrlens.Debit)
  assert_false(assets.is_abstract)
  assert_true(assets.nillable)
  let revenue = match
    schema.concept("http://fasb.org/us-gaap/2024", "Revenue") {
    Some(value) => value
    None => fail("missing Revenue concept")
  }
  assert_true(revenue.is_abstract)
  assert_eq(revenue.balance, @xbrlens.Credit)
  assert_eq(schema.role_types.length(), 1)
  assert_eq(schema.role_types[0].definition, Some("Statement roles"))
  assert_eq(schema.role_types[0].used_on.length(), 2)
  assert_eq(
    schema.role_types[0].used_on[0].expanded(),
    "{http://www.xbrl.org/2003/linkbase}presentationLink",
  )
}

///|
test "taxonomy parser rejects invalid roots and missing target namespaces" {
  assert_true(taxonomy_err("<schema/>") is @xbrlens.InvalidTaxonomy(_, _))
  assert_true(
    taxonomy_err("<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"/>")
    is @xbrlens.InvalidTaxonomy(_, _),
  )
}

///|
test "taxonomy parser rejects malformed concepts" {
  let prefix = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" targetNamespace=\"urn:t\">"
  assert_true(
    taxonomy_err(
      prefix +
      "<xs:element name=\"A\" substitutionGroup=\"xbrli:item\"/></xs:schema>",
    )
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  assert_true(
    taxonomy_err(
      prefix +
      "<xs:element name=\"A\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" periodType=\"year\"/></xs:schema>",
    )
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  assert_true(
    taxonomy_err(
      prefix +
      "<xs:element name=\"A\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\" balance=\"both\"/></xs:schema>",
    )
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  assert_true(
    taxonomy_err(
      prefix +
      "<xs:element name=\"A\" type=\"missing:Type\" substitutionGroup=\"xbrli:item\"/></xs:schema>",
    )
    is @xbrlens.MissingNamespace("missing", _),
  )
}

///|
test "taxonomy parser rejects duplicate concepts and role identifiers" {
  let prefix = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:link=\"http://www.xbrl.org/2003/linkbase\" targetNamespace=\"urn:t\">"
  let concept = "<xs:element name=\"A\" type=\"xbrli:monetaryItemType\" substitutionGroup=\"xbrli:item\"/>"
  assert_true(
    taxonomy_err(prefix + concept + concept + "</xs:schema>")
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  let role = "<link:roleType roleURI=\"urn:r\" id=\"r\"><link:usedOn>link:presentationLink</link:usedOn></link:roleType>"
  assert_true(
    taxonomy_err(prefix + role + role + "</xs:schema>")
    is @xbrlens.InvalidTaxonomy(_, _),
  )
}

///|
test "taxonomy parser rejects malformed role types and imports" {
  let prefix = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:link=\"http://www.xbrl.org/2003/linkbase\" targetNamespace=\"urn:t\">"
  assert_true(
    taxonomy_err(prefix + "<link:roleType id=\"r\"/></xs:schema>")
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  assert_true(
    taxonomy_err(prefix + "<xs:import schemaLocation=\"a.xsd\"/></xs:schema>")
    is @xbrlens.InvalidTaxonomy(_, _),
  )
  assert_true(
    taxonomy_err(
      prefix +
      "<link:roleType roleURI=\"urn:r\" id=\"r\"><link:usedOn>missing:Link</link:usedOn></link:roleType></xs:schema>",
    )
    is @xbrlens.MissingNamespace("missing", _),
  )
}
