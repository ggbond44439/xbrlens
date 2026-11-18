///|
pub(all) enum FactDiagnosticSeverity {
  Error
  Warning
} derive(Eq, @debug.Debug)

///|
pub(all) enum FactDiagnosticKind {
  ExactDuplicate
  ConflictingDuplicate
  NilConflict
  MultipleUnits
  DecimalsPrecisionConflict
  InvalidDecimals
  InvalidPrecision
} derive(Eq, @debug.Debug)

///|
pub(all) struct FactDiagnostic {
  kind : FactDiagnosticKind
  severity : FactDiagnosticSeverity
  concept : QName
  context_ref : String
  unit_ref : String?
  fact_ids : Array[String]
  message : String
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct FactIntegrityReport {
  diagnostics : Array[FactDiagnostic]
} derive(Eq, @debug.Debug)

///|
pub fn FactIntegrityReport::has_errors(self : FactIntegrityReport) -> Bool {
  for diagnostic in self.diagnostics {
    if diagnostic.severity == Error {
      return true
    }
  }
  false
}

///|
pub fn FactIntegrityReport::error_count(self : FactIntegrityReport) -> Int32 {
  let mut count = 0
  for diagnostic in self.diagnostics {
    if diagnostic.severity == Error {
      count += 1
    }
  }
  count
}

///|
pub fn FactIntegrityReport::warning_count(self : FactIntegrityReport) -> Int32 {
  let mut count = 0
  for diagnostic in self.diagnostics {
    if diagnostic.severity == Warning {
      count += 1
    }
  }
  count
}

///|
priv struct FactAspectGroup {
  concept : QName
  context_ref : String
  unit_ref : String?
  language : String?
  facts : Array[XbrlFact]
}

///|
priv struct FactAspectUnitVariant {
  concept : QName
  context_ref : String
  units : Array[String]
  facts : Array[XbrlFact]
}

///|
fn same_optional_string(left : String?, right : String?) -> Bool {
  match left {
    Some(left_value) =>
      match right {
        Some(right_value) => left_value == right_value
        None => false
      }
    None =>
      match right {
        Some(_) => false
        None => true
      }
  }
}

///|
fn find_aspect_group(groups : Array[FactAspectGroup], fact : XbrlFact) -> Int32 {
  let mut index = 0
  while index < groups.length() {
    let group = groups[index]
    if group.concept == fact.concept &&
      group.context_ref == fact.context_ref &&
      same_optional_string(group.unit_ref, fact.unit_ref) &&
      same_optional_string(group.language, fact.language) {
      return index
    }
    index += 1
  }
  -1
}

///|
fn fact_value_key(fact : XbrlFact) -> String {
  if fact.nil {
    "nil"
  } else {
    match Decimal::parse(fact.value.trim()) {
      Ok(value) => "number:" + value.to_canonical_string()
      Err(_) => "text:" + fact.value
    }
  }
}

///|
fn collect_fact_ids(facts : Array[XbrlFact]) -> Array[String] {
  let result : Array[String] = []
  for fact in facts {
    match fact.id {
      Some(value) => result.push(value)
      None => ()
    }
  }
  result
} ///|

///|
fn fact_has_nil(facts : Array[XbrlFact]) -> Bool {
  for fact in facts {
    if fact.nil {
      return true
    }
  }
  false
}

///|
fn fact_values_consistent(facts : Array[XbrlFact]) -> Bool {
  if facts.length() == 0 {
    return true
  }
  let expected = fact_value_key(facts[0])
  for fact in facts {
    if fact_value_key(fact) != expected {
      return false
    }
  }
  true
}

///|
fn valid_integer_text(
  value : StringView,
  allow_inf : Bool,
  positive_only : Bool,
) -> Bool {
  let text = value.trim()
  if allow_inf && text == "INF" {
    return true
  }
  if text.length() == 0 {
    return false
  }
  let mut index = 0
  if text.at(0) == 43 || text.at(0) == 45 {
    if positive_only {
      return false
    }
    index += 1
  }
  if index == text.length() {
    return false
  }
  let mut has_nonzero = false
  while index < text.length() {
    let code = text.at(index)
    if code < 48 || code > 57 {
      return false
    }
    if code != 48 {
      has_nonzero = true
    }
    index += 1
  }
  if positive_only && !has_nonzero {
    return false
  }
  true
}

///|
fn metadata_diagnostic(
  fact : XbrlFact,
  kind : FactDiagnosticKind,
  message : String,
) -> FactDiagnostic {
  {
    kind,
    severity: Error,
    concept: fact.concept,
    context_ref: fact.context_ref,
    unit_ref: fact.unit_ref,
    fact_ids: collect_fact_ids([fact]),
    message,
    offset: fact.offset,
  }
} ///|

///|
fn all_facts_nil(facts : Array[XbrlFact]) -> Bool {
  for fact in facts {
    if !fact.nil {
      return false
    }
  }
  true
}

///|
pub fn check_fact_integrity(instance : XbrlInstance) -> FactIntegrityReport {
  let diagnostics : Array[FactDiagnostic] = []
  let groups : Array[FactAspectGroup] = []
  for fact in instance.facts {
    match fact.decimals {
      Some(value) =>
        if !valid_integer_text(value, true, false) {
          diagnostics.push(
            metadata_diagnostic(
              fact,
              InvalidDecimals,
              "decimals must be an integer or INF",
            ),
          )
        }
      None => ()
    }
    match fact.precision {
      Some(value) =>
        if !valid_integer_text(value, false, true) {
          diagnostics.push(
            metadata_diagnostic(
              fact,
              InvalidPrecision,
              "precision must be a positive integer",
            ),
          )
        }
      None => ()
    }
    if fact.decimals is Some(_) && fact.precision is Some(_) {
      diagnostics.push(
        metadata_diagnostic(
          fact,
          DecimalsPrecisionConflict,
          "fact cannot specify both decimals and precision",
        ),
      )
    }
    let group_index = find_aspect_group(groups, fact)
    if group_index >= 0 {
      groups[group_index].facts.push(fact)
    } else {
      groups.push({
        concept: fact.concept,
        context_ref: fact.context_ref,
        unit_ref: fact.unit_ref,
        language: fact.language,
        facts: [fact],
      })
    }
  }
  for group in groups {
    if group.facts.length() > 1 {
      let has_nil = fact_has_nil(group.facts)
      if has_nil && !all_facts_nil(group.facts) {
        diagnostics.push({
          kind: NilConflict,
          severity: Error,
          concept: group.concept,
          context_ref: group.context_ref,
          unit_ref: group.unit_ref,
          fact_ids: collect_fact_ids(group.facts),
          message: "nil and non-nil facts share the same aspects",
          offset: group.facts[0].offset,
        })
      } else if fact_values_consistent(group.facts) {
        diagnostics.push({
          kind: ExactDuplicate,
          severity: Warning,
          concept: group.concept,
          context_ref: group.context_ref,
          unit_ref: group.unit_ref,
          fact_ids: collect_fact_ids(group.facts),
          message: "duplicate facts have equivalent values",
          offset: group.facts[0].offset,
        })
      } else {
        diagnostics.push({
          kind: ConflictingDuplicate,
          severity: Error,
          concept: group.concept,
          context_ref: group.context_ref,
          unit_ref: group.unit_ref,
          fact_ids: collect_fact_ids(group.facts),
          message: "duplicate facts have conflicting values",
          offset: group.facts[0].offset,
        })
      }
    }
  }
  let variants : Array[FactAspectUnitVariant] = []
  for group in groups {
    let unit_key = match group.unit_ref {
      Some(value) => value
      None => ""
    }
    let mut index = 0
    let mut found = -1
    while index < variants.length() {
      let variant = variants[index]
      if variant.concept == group.concept &&
        variant.context_ref == group.context_ref {
        found = index
        break
      }
      index += 1
    }
    if found >= 0 {
      let variant = variants[found]
      let mut known = false
      for value in variant.units {
        if value == unit_key {
          known = true
        }
      }
      if !known {
        variant.units.push(unit_key)
      }
      for fact in group.facts {
        variant.facts.push(fact)
      }
    } else {
      variants.push({
        concept: group.concept,
        context_ref: group.context_ref,
        units: [unit_key],
        facts: group.facts,
      })
    }
  }
  for variant in variants {
    if variant.units.length() > 1 {
      diagnostics.push({
        kind: MultipleUnits,
        severity: Warning,
        concept: variant.concept,
        context_ref: variant.context_ref,
        unit_ref: None,
        fact_ids: collect_fact_ids(variant.facts),
        message: "facts for the same concept and context use multiple units",
        offset: variant.facts[0].offset,
      })
    }
  }
  { diagnostics, }
}

///|
pub fn XbrlInstance::fact_integrity(self : XbrlInstance) -> FactIntegrityReport {
  check_fact_integrity(self)
}

///|
pub extend FactDiagnosticSeverity with Eq::{not_equal, equal}

///|
pub extend FactDiagnosticSeverity with @debug.Debug::{to_repr}

///|
pub extend FactDiagnosticKind with Eq::{not_equal, equal}

///|
pub extend FactDiagnosticKind with @debug.Debug::{to_repr}

///|
pub extend FactDiagnostic with Eq::{not_equal, equal}

///|
pub extend FactDiagnostic with @debug.Debug::{to_repr}

///|
pub extend FactIntegrityReport with Eq::{not_equal, equal}

///|
pub extend FactIntegrityReport with @debug.Debug::{to_repr}
