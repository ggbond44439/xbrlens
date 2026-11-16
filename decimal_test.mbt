///|
fn decimal_ok(value : StringView) -> @xbrlens.Decimal raise {
  match @xbrlens.Decimal::parse(value) {
    Ok(decimal) => decimal
    Err(err) => fail(err.to_string())
  }
}

///|
fn decimal_err(value : StringView) -> @xbrlens.XbrlError raise {
  match @xbrlens.Decimal::parse(value) {
    Ok(_) => fail("expected decimal parsing to fail")
    Err(err) => err
  }
}

///|
test "decimal parser normalizes signs zeros and fractional digits" {
  assert_eq(decimal_ok("00123.45000").to_canonical_string(), "123.45")
  assert_eq(decimal_ok("+42").to_canonical_string(), "42")
  assert_eq(decimal_ok("-0.000").to_canonical_string(), "0")
  assert_eq(decimal_ok(".5").to_canonical_string(), "0.5")
  assert_eq(decimal_ok("5.").to_canonical_string(), "5")
  assert_eq(decimal_ok("  -0.00120  ").to_canonical_string(), "-0.0012")
}

///|
test "decimal parser preserves large integer precision" {
  let value = decimal_ok("123456789012345678901234567890.1234567890123456789")
  assert_eq(
    value.to_canonical_string(),
    "123456789012345678901234567890.1234567890123456789",
  )
}

///|
test "decimal parser rejects invalid lexical forms" {
  assert_true(decimal_err("") is @xbrlens.InvalidDecimal(_, _))
  assert_true(decimal_err("+") is @xbrlens.InvalidDecimal(_, _))
  assert_true(decimal_err(".") is @xbrlens.InvalidDecimal(_, _))
  assert_true(decimal_err("1.2.3") is @xbrlens.InvalidDecimal(_, _))
  assert_true(decimal_err("1e3") is @xbrlens.InvalidDecimal(_, _))
  assert_true(decimal_err("1 2") is @xbrlens.InvalidDecimal(_, _))
}

///|
test "decimal arithmetic is exact and normalizes results" {
  let a = decimal_ok("0.1")
  let b = decimal_ok("0.2")
  let sum = match a.add(b, 0) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(sum.to_canonical_string(), "0.3")
  let difference = match decimal_ok("100.00").sub(decimal_ok("0.25"), 0) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(difference.to_canonical_string(), "99.75")
  let product = match decimal_ok("1.25").mul(decimal_ok("-0.4"), 0) {
    Ok(value) => value
    Err(err) => fail(err.to_string())
  }
  assert_eq(product.to_canonical_string(), "-0.5")
  assert_eq(decimal_ok("0.5").neg().to_canonical_string(), "-0.5")
}

///|
test "decimal comparison aligns fractional scales" {
  assert_eq(decimal_ok("1.20").compare(decimal_ok("1.2")), 0)
  assert_true(decimal_ok("1.201").compare(decimal_ok("1.2")) > 0)
  assert_true(decimal_ok("-2").compare(decimal_ok("-1.99")) < 0)
}

///|
test "decimal scaling exposes exact integer coefficients" {
  let value = decimal_ok("12.34")
  assert_eq(value.to_scaled_integer(4).unwrap().to_string(), "123400")
  assert_true(decimal_log_error(value) is @xbrlens.InvalidDecimal(_, _))
}

///|
fn decimal_log_error(value : @xbrlens.Decimal) -> @xbrlens.XbrlError raise {
  match value.to_scaled_integer(1) {
    Ok(_) => fail("expected scaling to fail")
    Err(err) => err
  }
}
