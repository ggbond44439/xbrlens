///|
#derive(Eq, @debug.Debug)
pub(all) struct CalculationCheck {
  role_uri : String
  parent : QName
  context_ref : String
  expected : Decimal
  expected_low : Decimal
  expected_high : Decimal
  actual : Decimal
  actual_low : Decimal
  actual_high : Decimal
  matched : Bool
  child_count : Int32
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct CalculationReport {
  checks : Array[CalculationCheck]
}

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
      let parent_context = match fact_context_signature(instance, parent_fact) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let parent_unit = match fact_unit_signature(instance, parent_fact) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let actual = match numeric_fact_value(parent_fact) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let actual_half = match fact_half_unit(parent_fact) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let mut expected = Decimal::zero()
      let mut expected_half = Decimal::zero()
      let mut child_count = 0
      for relation in group.relations {
        for child_fact in instance.facts {
          if child_fact.nil || child_fact.concept != relation.child {
            continue
          }
          let child_context = match
            fact_context_signature(instance, child_fact) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if child_context != parent_context {
            continue
          }
          let child_unit = match fact_unit_signature(instance, child_fact) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if child_unit != parent_unit {
            return Err(
              InvalidFact(
                "calculation facts use different unit semantics",
                child_fact.offset,
              ),
            )
          }
          let child_value = match numeric_fact_value(child_fact) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let child_half = match fact_half_unit(child_fact) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let weighted = match
            child_value.mul(relation.weight, child_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let weight_abs = if relation.weight.compare(Decimal::zero()) < 0 {
            relation.weight.neg()
          } else {
            relation.weight
          }
          let weighted_half = match
            child_half.mul(weight_abs, child_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          expected = match expected.add(weighted, parent_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          expected_half = match
            expected_half.add(weighted_half, parent_fact.offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          child_count += 1
        }
      }
      if child_count == 0 {
        continue
      }
      let expected_low = match expected.sub(expected_half, parent_fact.offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expected_high = match
        expected.add(expected_half, parent_fact.offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let actual_low = match actual.sub(actual_half, parent_fact.offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let actual_high = match actual.add(actual_half, parent_fact.offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      checks.push({
        role_uri: group.role_uri,
        parent: group.parent,
        context_ref: parent_fact.context_ref,
        expected,
        expected_low,
        expected_high,
        actual,
        actual_low,
        actual_high,
        matched: range_overlap(
          expected_low, expected_high, actual_low, actual_high,
        ),
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
