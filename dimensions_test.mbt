///|
fn dimension_instance_ok(source : StringView) -> @xbrlens.XbrlInstance raise {
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
}

///|
fn dimension_instance_err(source : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(_) => fail("expected dimension parsing to fail")
    Err(err) => err
  }
}

///|
fn dimension_context_source(
  segment_body : String,
  scenario_body : String,
) -> String {
  "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:xbrldi=\"http://xbrl.org/2006/xbrldi\" xmlns:gaap=\"urn:gaap\" xmlns:custom=\"urn:custom\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier><xbrli:segment>" +
  segment_body +
  "</xbrli:segment></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period><xbrli:scenario>" +
  scenario_body +
  "</xbrli:scenario></xbrli:context></xbrli:xbrl>"
}

///|
test "dimensions parser reads explicit and typed members from segment and scenario" {
  let source = dimension_context_source(
    "<xbrldi:explicitMember dimension=\"gaap:SegmentAxis\">gaap:RetailMember</xbrldi:explicitMember>",
    "<xbrldi:typedMember dimension=\"custom:DateAxis\"><custom:year>2024</custom:year></xbrldi:typedMember>",
  )
  let instance = dimension_instance_ok(source)
  let context = match instance.context("c") {
    Some(value) => value
    None => fail("missing context")
  }
  assert_eq(context.dimensions.length(), 2)
  assert_true(context.segment is Some(_))
  assert_true(context.scenario is Some(_))
  let segment_axis = match @xbrlens.QName::new("urn:gaap", "SegmentAxis") {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  match context.dimension(segment_axis) {
    Some(@xbrlens.Explicit(dimension, member_name)) => {
      assert_eq(dimension.expanded(), "{urn:gaap}SegmentAxis")
      assert_eq(member_name.expanded(), "{urn:gaap}RetailMember")
    }
    _ => fail("missing explicit dimension")
  }
  let date_axis = match @xbrlens.QName::new("urn:custom", "DateAxis") {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  match context.dimension(date_axis) {
    Some(@xbrlens.Typed(dimension, member_name, value)) => {
      assert_eq(dimension.expanded(), "{urn:custom}DateAxis")
      assert_eq(member_name.expanded(), "{urn:custom}year")
      assert_eq(value, "2024")
    }
    _ => fail("missing typed dimension")
  }
}

///|
test "dimensions parser accepts contexts without dimensions" {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context></xbrli:xbrl>"
  let instance = dimension_instance_ok(source)
  let context = match instance.context("c") {
    Some(value) => value
    None => fail("missing context")
  }
  assert_eq(context.dimensions.length(), 0)
  assert_true(context.segment is None)
  assert_true(context.scenario is None)
}

///|
test "dimensions parser rejects duplicate dimensions across segment and scenario" {
  let source = dimension_context_source(
    "<xbrldi:explicitMember dimension=\"gaap:SegmentAxis\">gaap:RetailMember</xbrldi:explicitMember>",
    "<xbrldi:explicitMember dimension=\"gaap:SegmentAxis\">gaap:WholesaleMember</xbrldi:explicitMember>",
  )
  assert_true(dimension_instance_err(source) is @xbrlens.InvalidDimension(_, _))
}

///|
test "dimensions parser rejects malformed explicit and typed members" {
  let missing_attribute = dimension_context_source(
    "<xbrldi:explicitMember>gaap:RetailMember</xbrldi:explicitMember>", "",
  )
  assert_true(
    dimension_instance_err(missing_attribute) is @xbrlens.InvalidDimension(_, _),
  )
  let explicit_with_child = dimension_context_source(
    "<xbrldi:explicitMember dimension=\"gaap:SegmentAxis\"><gaap:RetailMember/></xbrldi:explicitMember>",
    "",
  )
  assert_true(
    dimension_instance_err(explicit_with_child)
    is @xbrlens.InvalidDimension(_, _),
  )
  let typed_without_child = dimension_context_source(
    "", "<xbrldi:typedMember dimension=\"custom:DateAxis\"></xbrldi:typedMember>",
  )
  assert_true(
    dimension_instance_err(typed_without_child)
    is @xbrlens.InvalidDimension(_, _),
  )
  let unknown_prefix = dimension_context_source(
    "<xbrldi:explicitMember dimension=\"missing:Axis\">gaap:RetailMember</xbrldi:explicitMember>",
    "",
  )
  assert_true(
    dimension_instance_err(unknown_prefix)
    is @xbrlens.MissingNamespace("missing", _),
  )
}
