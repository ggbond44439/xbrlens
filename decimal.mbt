///|
const DECIMAL_MAX_DIGITS : Int32 = 1024

///|
const DECIMAL_MAX_SCALE : Int32 = 128

///|
pub(all) struct Decimal {
  coefficient : @bigint.BigInt
  scale : Int32
} derive(Eq, @debug.Debug)

///|
fn decimal_pow10(exponent : Int32) -> @bigint.BigInt {
  let builder = StringBuilder()
  builder.write_char('1')
  let mut index = 0
  while index < exponent {
    builder.write_char('0')
    index += 1
  }
  @bigint.BigInt::from_string(builder.to_string())
}

///|
fn decimal_digit_count(value : @bigint.BigInt) -> Int32 {
  let text = value.to_string()
  let offset = if text.has_prefix("-") { 1 } else { 0 }
  text.length() - offset
}

///|
fn decimal_result(
  coefficient : @bigint.BigInt,
  scale : Int32,
  offset : Int32,
) -> Result[Decimal, XbrlError] {
  if scale < 0 || scale > DECIMAL_MAX_SCALE {
    return Err(InvalidDecimal("scale exceeds the supported limit", offset))
  }
  if decimal_digit_count(coefficient) > DECIMAL_MAX_DIGITS {
    return Err(
      InvalidDecimal("coefficient exceeds the supported limit", offset),
    )
  }
  Ok(Decimal::normalize({ coefficient, scale, }))
}

///|
pub fn Decimal::zero() -> Decimal {
  { coefficient: @bigint.BigInt::from_int(0), scale: 0, }
}

///|
pub fn Decimal::normalize(self : Decimal) -> Decimal {
  let mut coefficient = self.coefficient
  let mut scale = self.scale
  if coefficient.is_zero() {
    return { coefficient: @bigint.BigInt::from_int(0), scale: 0, }
  }
  while scale > 0 && (coefficient % @bigint.BigInt::from_int(10)).is_zero() {
    coefficient = coefficient / @bigint.BigInt::from_int(10)
    scale -= 1
  }
  { coefficient, scale, }
}

///|
pub fn Decimal::parse(value : StringView) -> Result[Decimal, XbrlError] {
  let text = value.trim()
  let length = text.length()
  if length == 0 {
    return Err(InvalidDecimal("decimal is empty", 0))
  }
  let mut index = 0
  let negative = text.at(0) == 45
  if negative || text.at(0) == 43 {
    index += 1
    if index == length {
      return Err(InvalidDecimal("decimal sign requires digits", index))
    }
  }
  let builder = StringBuilder()
  if negative {
    builder.write_char('-')
  }
  let mut digit_count = 0
  let mut fractional_digits = 0
  let mut seen_dot = false
  while index < length {
    let code = text.at(index)
    if code == 46 {
      if seen_dot {
        return Err(InvalidDecimal("decimal contains multiple points", index))
      }
      seen_dot = true
      index += 1
      continue
    }
    if !is_ascii_digit(code) {
      return Err(
        InvalidDecimal("decimal contains a non-digit character", index),
      )
    }
    builder.write_char(code.unsafe_to_char())
    digit_count += 1
    if seen_dot {
      fractional_digits += 1
    }
    if digit_count > DECIMAL_MAX_DIGITS {
      return Err(
        InvalidDecimal("coefficient exceeds the supported limit", index),
      )
    }
    if fractional_digits > DECIMAL_MAX_SCALE {
      return Err(InvalidDecimal("scale exceeds the supported limit", index))
    }
    index += 1
  }
  if digit_count == 0 {
    return Err(InvalidDecimal("decimal requires at least one digit", 0))
  }
  let coefficient = @bigint.BigInt::from_string(builder.to_string())
  Ok(Decimal::normalize({ coefficient, scale: fractional_digits, }))
}

///|
fn Decimal::scaled_coefficient(self : Decimal, scale : Int32) -> @bigint.BigInt {
  if scale == self.scale {
    self.coefficient
  } else {
    self.coefficient * decimal_pow10(scale - self.scale)
  }
}

///|
pub fn Decimal::compare(self : Decimal, other : Decimal) -> Int32 {
  let scale = if self.scale > other.scale { self.scale } else { other.scale }
  self.scaled_coefficient(scale).compare(other.scaled_coefficient(scale))
}

///|
pub fn Decimal::add(
  self : Decimal,
  other : Decimal,
  offset : Int32,
) -> Result[Decimal, XbrlError] {
  let scale = if self.scale > other.scale { self.scale } else { other.scale }
  decimal_result(
    self.scaled_coefficient(scale) + other.scaled_coefficient(scale),
    scale,
    offset,
  )
}

///|
pub fn Decimal::sub(
  self : Decimal,
  other : Decimal,
  offset : Int32,
) -> Result[Decimal, XbrlError] {
  let scale = if self.scale > other.scale { self.scale } else { other.scale }
  decimal_result(
    self.scaled_coefficient(scale) - other.scaled_coefficient(scale),
    scale,
    offset,
  )
}

///|
pub fn Decimal::mul(
  self : Decimal,
  other : Decimal,
  offset : Int32,
) -> Result[Decimal, XbrlError] {
  decimal_result(
    self.coefficient * other.coefficient,
    self.scale + other.scale,
    offset,
  )
}

///|
pub fn Decimal::neg(self : Decimal) -> Decimal {
  Decimal::normalize({ coefficient: -self.coefficient, scale: self.scale, })
}

///|
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.coefficient.is_zero()
}

///|
pub fn Decimal::to_canonical_string(self : Decimal) -> String {
  let normalized = Decimal::normalize(self)
  if normalized.coefficient.is_zero() {
    return "0"
  }
  let negative = normalized.coefficient.compare_int(0) < 0
  let absolute = if negative {
    -normalized.coefficient
  } else {
    normalized.coefficient
  }
  let digits = absolute.to_string()
  let sign = if negative { "-" } else { "" }
  if normalized.scale == 0 {
    sign + digits
  } else if digits.length() > normalized.scale {
    let split = digits.length() - normalized.scale
    sign +
    digits.view(start_offset=0, end_offset=split).to_owned() +
    "." +
    digits.view(start_offset=split).to_owned()
  } else {
    let builder = StringBuilder()
    builder.write_string(sign)
    builder.write_string("0.")
    let mut zeros = normalized.scale - digits.length()
    while zeros > 0 {
      builder.write_char('0')
      zeros -= 1
    }
    builder.write_string(digits)
    builder.to_string()
  }
}

///|
pub fn Decimal::to_scaled_integer(
  self : Decimal,
  scale : Int32,
) -> Result[@bigint.BigInt, XbrlError] {
  if scale < self.scale {
    return Err(
      InvalidDecimal("cannot scale decimal to fewer fractional digits", 0),
    )
  }
  Ok(self.scaled_coefficient(scale))
}

///|
pub extend Decimal with Eq::{not_equal, equal}

///|
pub extend Decimal with @debug.Debug::{to_repr}
