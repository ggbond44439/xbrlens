///|
fn parse_accuracy_integer(
  value : StringView,
  offset : Int32,
) -> Result[Int32, XbrlError] {
  let text = value.trim()
  if text.length() == 0 {
    return Err(InvalidFact("numeric accuracy metadata is empty", offset))
  }
  let mut index = 0
  let negative = text.at(0) == 45
  if negative || text.at(0) == 43 {
    index += 1
  }
  if index == text.length() {
    return Err(InvalidFact("numeric accuracy metadata is invalid", offset))
  }
  let mut result : Int32 = 0
  while index < text.length() {
    let code = text.at(index)
    if code < 48 || code > 57 {
      return Err(InvalidFact("numeric accuracy metadata is invalid", offset))
    }
    result = result * 10 + code.to_int() - 48
    index += 1
  }
  Ok(if negative { -result } else { result })
}

///|
fn decimal_order(value : Decimal) -> Int32 {
  if value.is_zero() {
    return 0
  }
  let text = value.to_canonical_string()
  let sign_offset = if text.has_prefix("-") { 1 } else { 0 }
  let mut dot = text.length()
  let mut index = sign_offset
  while index < text.length() {
    if text.at(index) == 46 {
      dot = index
      break
    }
    index += 1
  }
  let integer_digits = dot - sign_offset
  if integer_digits > 1 || (integer_digits == 1 && text.at(sign_offset) != 48) {
    return integer_digits - 1
  }
  let mut fraction_index = dot + 1
  while fraction_index < text.length() {
    if text.at(fraction_index) != 48 {
      return -(fraction_index - dot)
    }
    fraction_index += 1
  }
  0
}

///|
fn half_unit_from_exponent(
  exponent : Int32,
  offset : Int32,
) -> Result[Decimal, XbrlError] {
  if exponent > 128 || exponent < -128 {
    return Err(
      InvalidFact("numeric accuracy exponent is out of bounds", offset),
    )
  }
  let builder = StringBuilder()
  if exponent == 0 {
    builder.write_string("0.5")
  } else if exponent > 0 {
    builder.write_char('5')
    let mut index = 1
    while index < exponent {
      builder.write_char('0')
      index += 1
    }
  } else {
    builder.write_string("0.")
    let mut index = 0
    while index < -exponent {
      builder.write_char('0')
      index += 1
    }
    builder.write_char('5')
  }
  Decimal::parse(builder.to_string())
}

///|
fn fact_half_unit(fact : XbrlFact) -> Result[Decimal, XbrlError] {
  match fact.decimals {
    Some(value) if value.trim() == "INF" => Ok(Decimal::zero())
    Some(value) => {
      let decimals = match parse_accuracy_integer(value, fact.offset) {
        Ok(number) => number
        Err(err) => return Err(err)
      }
      half_unit_from_exponent(-decimals, fact.offset)
    }
    None =>
      match fact.precision {
        Some(value) => {
          let precision = match parse_accuracy_integer(value, fact.offset) {
            Ok(number) if number > 0 => number
            _ =>
              return Err(
                InvalidFact("precision must be a positive integer", fact.offset),
              )
          }
          let value = match numeric_fact_value(fact) {
            Ok(number) => number
            Err(err) => return Err(err)
          }
          half_unit_from_exponent(
            decimal_order(value) - precision + 1,
            fact.offset,
          )
        }
        None =>
          Err(
            InvalidFact(
              "numeric calculation fact requires decimals or precision",
              fact.offset,
            ),
          )
      }
  }
}

///|
fn qname_array_signature(values : Array[QName]) -> String {
  let rendered : Array[String] = []
  for value in values {
    rendered.push(value.expanded())
  }
  rendered.sort_by((left, right) => {
    if left < right {
      -1
    } else if left > right {
      1
    } else {
      0
    }
  })
  let builder = StringBuilder()
  let mut index = 0
  while index < rendered.length() {
    if index > 0 {
      builder.write_char('*')
    }
    builder.write_string(rendered[index])
    index += 1
  }
  builder.to_string()
}

///|
fn unit_signature(unit : XbrlUnit) -> String {
  match unit {
    Simple(measure) => "simple:" + measure.expanded()
    Divide(numerator, denominator) =>
      "divide:" +
      qname_array_signature(numerator) +
      "/" +
      qname_array_signature(denominator)
  }
}

///|
fn xml_signature(node : XmlNode) -> String {
  let builder = StringBuilder()
  builder.write_char('<')
  builder.write_string(node.name.expanded())
  builder.write_char('>')
  builder.write_string(node.text)
  for child in node.children {
    builder.write_string(xml_signature(child))
  }
  builder.write_char('<')
  builder.write_char('/')
  builder.write_string(node.name.expanded())
  builder.write_char('>')
  builder.to_string()
}

///|
fn context_signature(context : XbrlContext) -> String {
  let period = match context.period {
    Instant(value) => "instant:" + value
    Duration(start, end) => "duration:" + start + "/" + end
  }
  let segment = match context.segment {
    Some(value) => xml_signature(value)
    None => ""
  }
  let scenario = match context.scenario {
    Some(value) => xml_signature(value)
    None => ""
  }
  "entity:" +
  context.entity_scheme +
  "|" +
  context.entity_identifier +
  "|" +
  period +
  "|" +
  segment +
  "|" +
  scenario
}

///|
fn fact_context_signature(
  instance : XbrlInstance,
  fact : XbrlFact,
) -> Result[String, XbrlError] {
  match instance.context(fact.context_ref) {
    Some(context) => Ok(context_signature(context))
    None =>
      Err(
        InvalidContext(
          "calculation fact references a missing context",
          fact.offset,
        ),
      )
  }
}

///|
fn fact_unit_signature(
  instance : XbrlInstance,
  fact : XbrlFact,
) -> Result[String, XbrlError] {
  match fact.unit_ref {
    Some(unit_id) =>
      match instance.unit(unit_id) {
        Some(definition) => Ok(unit_signature(definition.unit))
        None =>
          Err(
            InvalidUnit(
              "calculation fact references a missing unit",
              fact.offset,
            ),
          )
      }
    None => Err(InvalidFact("calculation fact has no unit", fact.offset))
  }
}

///|
fn range_overlap(
  left_low : Decimal,
  left_high : Decimal,
  right_low : Decimal,
  right_high : Decimal,
) -> Bool {
  left_high.compare(right_low) >= 0 && right_high.compare(left_low) >= 0
}
