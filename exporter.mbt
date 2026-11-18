///|
pub(all) struct FactExportRow {
  fact_id : String?
  concept : String
  namespace_uri : String
  local_name : String
  context_ref : String
  entity_scheme : String
  entity_identifier : String
  period_type : String
  instant : String?
  start_date : String?
  end_date : String?
  unit_ref : String?
  unit : String?
  value : String
  canonical_value : String?
  nil : Bool
  decimals : String?
  precision : String?
  language : String?
  dimensions_json : String
} derive(Eq, @debug.Debug)

///|
fn export_qname_list(values : Array[QName]) -> String {
  let builder = StringBuilder()
  let mut index = 0
  while index < values.length() {
    if index > 0 {
      builder.write_char('*')
    }
    builder.write_string(values[index].expanded())
    index += 1
  }
  builder.to_string()
}

///|
fn export_unit_string(unit : XbrlUnit) -> String {
  match unit {
    Simple(measure) => measure.expanded()
    Divide(numerator, denominator) =>
      export_qname_list(numerator) + "/" + export_qname_list(denominator)
  }
}

///|
fn json_hex_char(value : Int32) -> Char {
  if value < 10 {
    (value + 48).unsafe_to_char()
  } else {
    (value + 87).unsafe_to_char()
  }
}

///|
fn json_quote(value : String) -> String {
  let builder = StringBuilder()
  builder.write_char('"')
  for character in value {
    let code = character.to_int()
    if code == 34 {
      builder.write_string("\\\"")
    } else if code == 92 {
      builder.write_string("\\\\")
    } else if code == 8 {
      builder.write_string("\\b")
    } else if code == 9 {
      builder.write_string("\\t")
    } else if code == 10 {
      builder.write_string("\\n")
    } else if code == 12 {
      builder.write_string("\\f")
    } else if code == 13 {
      builder.write_string("\\r")
    } else if code < 32 {
      builder.write_string("\\u00")
      builder.write_char(json_hex_char((code >> 4) & 15))
      builder.write_char(json_hex_char(code & 15))
    } else {
      builder.write_char(character)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn json_optional(value : String?) -> String {
  match value {
    Some(text) => json_quote(text)
    None => "null"
  }
}

///|
fn dimensions_json(dimensions : Array[DimensionMember]) -> String {
  let builder = StringBuilder()
  builder.write_char('[')
  let mut index = 0
  while index < dimensions.length() {
    if index > 0 {
      builder.write_char(',')
    }
    match dimensions[index] {
      Explicit(dimension, member_name) => {
        builder.write_string("{\"dimension\":")
        builder.write_string(json_quote(dimension.expanded()))
        builder.write_string(",\"kind\":\"explicit\",\"member\":")
        builder.write_string(json_quote(member_name.expanded()))
        builder.write_char('}')
      }
      Typed(dimension, member_name, value) => {
        builder.write_string("{\"dimension\":")
        builder.write_string(json_quote(dimension.expanded()))
        builder.write_string(",\"kind\":\"typed\",\"member\":")
        builder.write_string(json_quote(member_name.expanded()))
        builder.write_string(",\"value\":")
        builder.write_string(json_quote(value))
        builder.write_char('}')
      }
    }
    index += 1
  }
  builder.write_char(']')
  builder.to_string()
} ///|

///|
pub fn export_rows(
  instance : XbrlInstance,
) -> Result[Array[FactExportRow], XbrlError] {
  let rows : Array[FactExportRow] = []
  for fact in instance.facts {
    let context = match instance.context(fact.context_ref) {
      Some(value) => value
      None =>
        return Err(
          InvalidContext("fact references a missing context", fact.offset),
        )
    }
    let unit = match fact.unit_ref {
      Some(unit_id) =>
        match instance.unit(unit_id) {
          Some(value) => Some(export_unit_string(value.unit))
          None =>
            return Err(
              InvalidUnit("fact references a missing unit", fact.offset),
            )
        }
      None => None
    }
    let (period_type, instant, start_date, end_date) = match context.period {
      Instant(value) => ("instant", Some(value), None, None)
      Duration(start, end) => ("duration", None, Some(start), Some(end))
    }
    let canonical_value = if fact.nil {
      None
    } else {
      match Decimal::parse(fact.value.trim()) {
        Ok(value) => Some(value.to_canonical_string())
        Err(_) => None
      }
    }
    rows.push({
      fact_id: fact.id,
      concept: fact.concept.expanded(),
      namespace_uri: fact.concept.namespace_uri,
      local_name: fact.concept.local_name,
      context_ref: fact.context_ref,
      entity_scheme: context.entity_scheme,
      entity_identifier: context.entity_identifier,
      period_type,
      instant,
      start_date,
      end_date,
      unit_ref: fact.unit_ref,
      unit,
      value: fact.value,
      canonical_value,
      nil: fact.nil,
      decimals: fact.decimals,
      precision: fact.precision,
      language: fact.language,
      dimensions_json: dimensions_json(context.dimensions),
    })
  }
  Ok(rows)
}

///|
fn row_json(row : FactExportRow) -> String {
  let builder = StringBuilder()
  builder.write_char('{')
  builder.write_string("\"factId\":")
  builder.write_string(json_optional(row.fact_id))
  builder.write_string(",\"concept\":")
  builder.write_string(json_quote(row.concept))
  builder.write_string(",\"namespace\":")
  builder.write_string(json_quote(row.namespace_uri))
  builder.write_string(",\"localName\":")
  builder.write_string(json_quote(row.local_name))
  builder.write_string(",\"contextRef\":")
  builder.write_string(json_quote(row.context_ref))
  builder.write_string(",\"entityScheme\":")
  builder.write_string(json_quote(row.entity_scheme))
  builder.write_string(",\"entityIdentifier\":")
  builder.write_string(json_quote(row.entity_identifier))
  builder.write_string(",\"periodType\":")
  builder.write_string(json_quote(row.period_type))
  builder.write_string(",\"instant\":")
  builder.write_string(json_optional(row.instant))
  builder.write_string(",\"startDate\":")
  builder.write_string(json_optional(row.start_date))
  builder.write_string(",\"endDate\":")
  builder.write_string(json_optional(row.end_date))
  builder.write_string(",\"unitRef\":")
  builder.write_string(json_optional(row.unit_ref))
  builder.write_string(",\"unit\":")
  builder.write_string(json_optional(row.unit))
  builder.write_string(",\"value\":")
  builder.write_string(json_quote(row.value))
  builder.write_string(",\"canonicalValue\":")
  builder.write_string(json_optional(row.canonical_value))
  builder.write_string(",\"nil\":")
  builder.write_string(if row.nil { "true" } else { "false" })
  builder.write_string(",\"decimals\":")
  builder.write_string(json_optional(row.decimals))
  builder.write_string(",\"precision\":")
  builder.write_string(json_optional(row.precision))
  builder.write_string(",\"language\":")
  builder.write_string(json_optional(row.language))
  builder.write_string(",\"dimensions\":")
  builder.write_string(row.dimensions_json)
  builder.write_char('}')
  builder.to_string()
}

///|
pub fn export_json(instance : XbrlInstance) -> Result[String, XbrlError] {
  let rows = match export_rows(instance) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let builder = StringBuilder()
  builder.write_char('[')
  let mut index = 0
  while index < rows.length() {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(row_json(rows[index]))
    index += 1
  }
  builder.write_char(']')
  Ok(builder.to_string())
} ///|

///|
fn csv_field(value : String) -> String {
  let mut needs_quotes = false
  for character in value {
    let code = character.to_int()
    if code == 34 || code == 44 || code == 10 || code == 13 {
      needs_quotes = true
    }
  }
  if !needs_quotes {
    return value
  }
  let builder = StringBuilder()
  builder.write_char('"')
  for character in value {
    if character.to_int() == 34 {
      builder.write_string("\"\"")
    } else {
      builder.write_char(character)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn csv_optional(value : String?) -> String {
  match value {
    Some(text) => csv_field(text)
    None => ""
  }
}

///|
pub fn export_csv(instance : XbrlInstance) -> Result[String, XbrlError] {
  let rows = match export_rows(instance) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let builder = StringBuilder()
  builder.write_string(
    "fact_id,concept,namespace,local_name,context_ref,entity_scheme,entity_identifier,period_type,instant,start_date,end_date,unit_ref,unit,value,canonical_value,nil,decimals,precision,language,dimensions_json\n",
  )
  for row in rows {
    builder.write_string(csv_optional(row.fact_id))
    builder.write_char(',')
    builder.write_string(csv_field(row.concept))
    builder.write_char(',')
    builder.write_string(csv_field(row.namespace_uri))
    builder.write_char(',')
    builder.write_string(csv_field(row.local_name))
    builder.write_char(',')
    builder.write_string(csv_field(row.context_ref))
    builder.write_char(',')
    builder.write_string(csv_field(row.entity_scheme))
    builder.write_char(',')
    builder.write_string(csv_field(row.entity_identifier))
    builder.write_char(',')
    builder.write_string(csv_field(row.period_type))
    builder.write_char(',')
    builder.write_string(csv_optional(row.instant))
    builder.write_char(',')
    builder.write_string(csv_optional(row.start_date))
    builder.write_char(',')
    builder.write_string(csv_optional(row.end_date))
    builder.write_char(',')
    builder.write_string(csv_optional(row.unit_ref))
    builder.write_char(',')
    builder.write_string(csv_optional(row.unit))
    builder.write_char(',')
    builder.write_string(csv_field(row.value))
    builder.write_char(',')
    builder.write_string(csv_optional(row.canonical_value))
    builder.write_char(',')
    builder.write_string(if row.nil { "true" } else { "false" })
    builder.write_char(',')
    builder.write_string(csv_optional(row.decimals))
    builder.write_char(',')
    builder.write_string(csv_optional(row.precision))
    builder.write_char(',')
    builder.write_string(csv_optional(row.language))
    builder.write_char(',')
    builder.write_string(csv_field(row.dimensions_json))
    builder.write_char('\n')
  }
  Ok(builder.to_string())
}

///|
pub extend FactExportRow with Eq::{not_equal, equal}

///|
pub extend FactExportRow with @debug.Debug::{to_repr}
