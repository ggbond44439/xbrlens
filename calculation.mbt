///|
pub(all) struct CalculationCheck {
  role_uri : String
  parent : QName
  context_ref : String
  expected : Decimal
  actual : Decimal
  matched : Bool
  child_count : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct CalculationReport {
  checks : Array[CalculationCheck]
} derive(Eq, @debug.Debug)

///|
pub fn CalculationReport::is_valid(self : CalculationReport) -> Bool {
  for check in self.checks {
    if !check.matched {
      return false
    }
  }
  true
}

///|
pub fn CalculationReport::mismatches(
  self : CalculationReport,
) -> Array[CalculationCheck] {
  let result : Array[CalculationCheck] = []
  for check in self.checks {
    if !check.matched {
      result.push(check)
    }
  }
  result
}

///|
fn numeric_fact_value(fact : XbrlFact) -> Result[Decimal, XbrlError] {
  match Decimal::parse(fact.value.trim()) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidFact("calculation fact is not a decimal", fact.offset))
  }
}

///|
fn calculation_unit_matches(
  parent : XbrlFact,
  child : XbrlFact,
) -> Result[Unit, XbrlError] {
  match parent.unit_ref {
    Some(parent_unit) =>
      match child.unit_ref {
        Some(child_unit) =>
          if parent_unit == child_unit {
            Ok(())
          } else {
            Err(
              InvalidFact("calculation facts use different units", child.offset),
            )
          }
        None =>
          Err(InvalidFact("calculation child fact has no unit", child.offset))
      }
    None =>
      Err(InvalidFact("calculation parent fact has no unit", parent.offset))
  }
}

///|
pub fn check_calculations(
  linkbase : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
  instance : XbrlInstance,
) -> Result[CalculationReport, XbrlError] {
  let groups = match linkbase.calculation_groups(taxonomy) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let checks : Array[CalculationCheck] = []
  for group in groups {
    for parent_fact in instance.facts {
      if parent_fact.nil || parent_fact.concept != group.parent {
        continue
      }
      let actual = match numeric_fact_value(parent_fact) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let mut expected = Decimal::zero()
      let mut child_count = 0
      for relation in group.relations {
        for child_fact in instance.facts {
          if child_fact.nil ||
            child_fact.concept != relation.child ||
            child_fact.context_ref != parent_fact.context_ref {
            continue
          }
          match calculation_unit_matches(parent_fact, child_fact) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let child_value = match numeric_fact_value(child_fact) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let weighted = match
            child_value.mul(relation.weight, child_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          expected = match expected.add(weighted, parent_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          child_count += 1
        }
      }
      if child_count == 0 {
        continue
      }
      checks.push({
        role_uri: group.role_uri,
        parent: group.parent,
        context_ref: parent_fact.context_ref,
        expected,
        actual,
        matched: expected.compare(actual) == 0,
        child_count,
      })
    }
  }
  Ok({ checks, })
}

///|
pub fn XbrlLinkbase::check_calculations(
  self : XbrlLinkbase,
  taxonomy : ResolvedTaxonomy,
  instance : XbrlInstance,
) -> Result[CalculationReport, XbrlError] {
  check_calculations(self, taxonomy, instance)
}

///|
pub extend CalculationCheck with Eq::{not_equal, equal}

///|
pub extend CalculationCheck with @debug.Debug::{to_repr}

///|
pub extend CalculationReport with Eq::{not_equal, equal}

///|
pub extend CalculationReport with @debug.Debug::{to_repr}
